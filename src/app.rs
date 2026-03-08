use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use crossbeam_channel::Receiver;
use eframe::egui::{self, Color32, KeyboardShortcut, Modifiers, RichText, Vec2};

use crate::binds::BindManager;
use crate::ipc::{AppCommand, CommandServer};
use crate::terminal::{TerminalTab, render_terminal};

pub fn run(initial_commands: Vec<AppCommand>, process_started: Instant) -> Result<()> {
    let (command_tx, command_rx) = crossbeam_channel::unbounded();
    let server = CommandServer::start(command_tx)?;
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("osmium")
            .with_inner_size(Vec2::new(1440.0, 920.0))
            .with_min_inner_size(Vec2::new(980.0, 640.0))
            .with_decorations(false)
            .with_transparent(true),
        ..Default::default()
    };

    let creator = move |cc: &eframe::CreationContext<'_>| -> Result<
        Box<dyn eframe::App>,
        Box<dyn std::error::Error + Send + Sync>,
    > {
        Ok(Box::new(OsmApp::bootstrap(
            cc,
            command_rx,
            server,
            initial_commands,
            process_started,
        )?))
    };

    eframe::run_native("osmium", options, Box::new(creator))
        .map_err(|error| anyhow::anyhow!("failed to launch osmium: {error}"))?;
    Ok(())
}

struct OsmApp {
    command_rx: Receiver<AppCommand>,
    server: CommandServer,
    binds: BindManager,
    tabs: Vec<Tab>,
    selected_tab_id: Option<u64>,
    left_split_id: Option<u64>,
    next_tab_id: u64,
    status: String,
    process_started: Instant,
    first_frame_logged: bool,
    exit_after: Option<Duration>,
}

struct EditorTab {
    id: u64,
    path: PathBuf,
    buffer: String,
    dirty: bool,
}

struct BrowserTab {
    id: u64,
    url: String,
    auto_open_external: bool,
    status: String,
}

enum Tab {
    Terminal(TerminalTab),
    Editor(EditorTab),
    Browser(BrowserTab),
}

impl OsmApp {
    fn bootstrap(
        cc: &eframe::CreationContext<'_>,
        command_rx: Receiver<AppCommand>,
        server: CommandServer,
        initial_commands: Vec<AppCommand>,
        process_started: Instant,
    ) -> Result<Self> {
        configure_theme(&cc.egui_ctx);

        let mut app = Self {
            command_rx,
            server,
            binds: BindManager::new()?,
            tabs: Vec::new(),
            selected_tab_id: None,
            left_split_id: None,
            next_tab_id: 1,
            status: "ready".to_owned(),
            process_started,
            first_frame_logged: false,
            exit_after: exit_after_from_env(),
        };

        for command in initial_commands {
            app.apply_command(command)?;
        }

        if app.tabs.is_empty() {
            app.open_terminal(std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))?;
        }

        Ok(app)
    }

    fn apply_command(&mut self, command: AppCommand) -> Result<()> {
        match command {
            AppCommand::OpenTerminal { cwd } => {
                let cwd = cwd.unwrap_or_else(|| {
                    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
                });
                self.open_terminal(cwd)?;
            }
            AppCommand::OpenEditor { path } => self.open_editor(path)?,
            AppCommand::OpenBrowser { url } => self.open_browser(url),
            AppCommand::AddBind { event, command } => {
                self.binds.add_bind(event.clone(), command.clone())?;
                self.status = format!("bound {event} -> {command}");
            }
        }

        Ok(())
    }

    fn open_terminal(&mut self, cwd: PathBuf) -> Result<()> {
        let id = self.alloc_tab_id();
        let tab = TerminalTab::spawn(id, cwd.clone())?;
        self.tabs.push(Tab::Terminal(tab));
        self.selected_tab_id = Some(id);
        self.status = format!("opened terminal in {}", cwd.display());
        Ok(())
    }

    fn open_editor(&mut self, path: PathBuf) -> Result<()> {
        if let Some(id) = self.find_editor(&path) {
            self.selected_tab_id = Some(id);
            self.status = format!("focused {}", path.display());
            return Ok(());
        }

        let contents = if path.exists() {
            fs::read_to_string(&path)
                .with_context(|| format!("failed to read {}", path.display()))?
        } else {
            String::new()
        };

        let id = self.alloc_tab_id();
        self.tabs.push(Tab::Editor(EditorTab {
            id,
            path: path.clone(),
            buffer: contents,
            dirty: false,
        }));
        self.selected_tab_id = Some(id);
        self.status = format!("opened {}", path.display());
        Ok(())
    }

    fn open_browser(&mut self, url: String) {
        let id = self.alloc_tab_id();
        self.tabs.push(Tab::Browser(BrowserTab {
            id,
            url: url.clone(),
            auto_open_external: true,
            status: "ready".to_owned(),
        }));
        self.selected_tab_id = Some(id);
        self.status = format!("opened browser target {url}");
    }

    fn drain_commands(&mut self) {
        while let Ok(command) = self.command_rx.try_recv() {
            if let Err(error) = self.apply_command(command) {
                self.status = format!("command error: {error:#}");
            }
        }
    }

    fn alloc_tab_id(&mut self) -> u64 {
        let id = self.next_tab_id;
        self.next_tab_id += 1;
        id
    }

    fn selected_tab_mut(&mut self) -> Option<&mut Tab> {
        let selected = self.selected_tab_id?;
        self.tabs.iter_mut().find(|tab| tab.id() == selected)
    }

    fn selected_tab(&self) -> Option<&Tab> {
        let selected = self.selected_tab_id?;
        self.tabs.iter().find(|tab| tab.id() == selected)
    }

    fn find_editor(&self, path: &Path) -> Option<u64> {
        self.tabs.iter().find_map(|tab| match tab {
            Tab::Editor(editor) if editor.path == path => Some(editor.id),
            _ => None,
        })
    }

    fn handle_shortcuts(&mut self, ctx: &egui::Context) {
        if consume_shortcut(ctx, Modifiers::COMMAND, egui::Key::T) {
            if let Err(error) =
                self.open_terminal(std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
            {
                self.status = format!("failed to open terminal: {error:#}");
            }
        }

        if consume_shortcut(
            ctx,
            Modifiers {
                command: true,
                shift: true,
                ..Default::default()
            },
            egui::Key::CloseBracket,
        ) {
            self.select_relative_tab(1);
        }

        if consume_shortcut(
            ctx,
            Modifiers {
                command: true,
                shift: true,
                ..Default::default()
            },
            egui::Key::OpenBracket,
        ) {
            self.select_relative_tab(-1);
        }

        if consume_shortcut(
            ctx,
            Modifiers {
                alt: true,
                ..Default::default()
            },
            egui::Key::CloseBracket,
        ) {
            if let Err(error) = self.split_left() {
                self.status = format!("split failed: {error:#}");
            }
        }

        if consume_shortcut(ctx, Modifiers::COMMAND, egui::Key::W) {
            self.close_selected_tab();
        }

        if consume_shortcut(ctx, Modifiers::COMMAND, egui::Key::S) {
            if let Err(error) = self.save_selected_editor() {
                self.status = format!("save failed: {error:#}");
            }
        }

        self.handle_terminal_input(ctx);
    }

    fn handle_terminal_input(&mut self, ctx: &egui::Context) {
        let Some(Tab::Terminal(terminal)) = self.selected_tab_mut() else {
            return;
        };

        let events = ctx.input(|input| input.events.clone());
        for event in events {
            match event {
                egui::Event::Text(text) => {
                    if !text.is_empty() {
                        terminal.send_text(&text);
                    }
                }
                egui::Event::Paste(text) => terminal.send_text(&text),
                egui::Event::Key {
                    key,
                    pressed: true,
                    modifiers,
                    ..
                } if !(modifiers.command || modifiers.mac_cmd) => {
                    let _ = terminal.handle_key(key, modifiers);
                }
                _ => {}
            }
        }
    }

    fn select_relative_tab(&mut self, delta: isize) {
        if self.tabs.is_empty() {
            return;
        }

        let current_index = self
            .selected_tab_id
            .and_then(|selected| self.tabs.iter().position(|tab| tab.id() == selected))
            .unwrap_or(0);
        let len = self.tabs.len() as isize;
        let next_index = (current_index as isize + delta).rem_euclid(len) as usize;
        self.selected_tab_id = Some(self.tabs[next_index].id());
    }

    fn split_left(&mut self) -> Result<()> {
        let Some(selected) = self.selected_tab_id else {
            return Ok(());
        };

        let new_id = match self.selected_tab() {
            Some(Tab::Editor(editor)) => {
                self.open_editor(editor.path.clone())?;
                self.selected_tab_id.unwrap_or(selected)
            }
            Some(Tab::Browser(browser)) => {
                self.open_browser(browser.url.clone());
                self.selected_tab_id.unwrap_or(selected)
            }
            Some(Tab::Terminal(_)) | None => {
                self.open_terminal(std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))?;
                self.selected_tab_id.unwrap_or(selected)
            }
        };

        self.left_split_id = Some(new_id);
        self.selected_tab_id = Some(selected);
        self.status = "split current workspace left".to_owned();
        Ok(())
    }

    fn close_selected_tab(&mut self) {
        let Some(selected) = self.selected_tab_id else {
            return;
        };
        self.tabs.retain(|tab| tab.id() != selected);
        if self.left_split_id == Some(selected) {
            self.left_split_id = None;
        }
        self.selected_tab_id = self.tabs.last().map(Tab::id);
        self.status = "closed tab".to_owned();
    }

    fn save_selected_editor(&mut self) -> Result<()> {
        let Some(selected) = self.selected_tab_id else {
            return Ok(());
        };
        let Some(index) = self.tabs.iter().position(|tab| tab.id() == selected) else {
            return Ok(());
        };
        let Tab::Editor(editor) = &mut self.tabs[index] else {
            return Ok(());
        };

        let path = editor.path.clone();
        let buffer = editor.buffer.clone();

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        fs::write(&path, buffer).with_context(|| format!("failed to save {}", path.display()))?;
        editor.dirty = false;

        let commands = self.binds.commands_for_save(&path);
        let save_dir = path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| PathBuf::from("."));
        for command in &commands {
            spawn_bind(command, &save_dir);
        }

        self.status = if let Some(command) = commands.last() {
            format!("saved {} and ran `{command}`", path.display())
        } else {
            format!("saved {}", path.display())
        };

        Ok(())
    }

    fn sidebar_visible(&self, ctx: &egui::Context) -> bool {
        ctx.input(|input| input.modifiers.command || input.modifiers.mac_cmd)
    }

    fn draw_overlay_chrome(&self, ctx: &egui::Context) {
        let active_title = self
            .selected_tab()
            .map(Tab::title)
            .unwrap_or_else(|| "blank".to_owned());
        let active_kind = self.selected_tab().map(Tab::kind_prefix).unwrap_or(" ");

        egui::Area::new("osmium_title".into())
            .fixed_pos(egui::pos2(18.0, 18.0))
            .show(ctx, |ui| {
                let response = glass_frame(
                    Color32::from_rgba_unmultiplied(235, 242, 251, 24),
                    Color32::from_rgba_unmultiplied(255, 255, 255, 52),
                )
                .inner_margin(egui::Margin::symmetric(16, 10))
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        ui.label(
                            RichText::new("osmium")
                                .strong()
                                .size(15.0)
                                .color(Color32::from_rgb(239, 244, 248)),
                        );
                        ui.label(
                            RichText::new(format!("{active_kind} {active_title}"))
                                .size(14.0)
                                .color(Color32::from_rgb(199, 212, 220)),
                        );
                    });
                })
                .response;

                if response.drag_started() {
                    ctx.send_viewport_cmd(egui::ViewportCommand::StartDrag);
                }
            });

        egui::Area::new("osmium_status".into())
            .anchor(egui::Align2::RIGHT_BOTTOM, egui::vec2(-18.0, -18.0))
            .show(ctx, |ui| {
                glass_frame(
                    Color32::from_rgba_unmultiplied(235, 242, 251, 20),
                    Color32::from_rgba_unmultiplied(255, 255, 255, 42),
                )
                    .inner_margin(egui::Margin::symmetric(14, 10))
                    .show(ui, |ui| {
                        ui.label(
                            RichText::new(self.status.clone())
                                .size(13.0)
                                .color(Color32::from_rgb(202, 225, 214)),
                        );
                    });
            });
    }

    fn maybe_emit_startup_stats(&mut self, ctx: &egui::Context) {
        if !self.first_frame_logged {
            self.first_frame_logged = true;
            if std::env::var_os("OSMIUM_BENCH_LOG").is_some() {
                eprintln!(
                    "osmium_first_frame_ms={}",
                    self.process_started.elapsed().as_millis()
                );
            }
        }

        if let Some(exit_after) = self.exit_after {
            if self.process_started.elapsed() >= exit_after {
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }
        }
    }

    fn show_sidebar(&mut self, ctx: &egui::Context) {
        if !self.sidebar_visible(ctx) {
            return;
        }

        egui::SidePanel::left("tabs")
            .resizable(false)
            .default_width(248.0)
            .show(ctx, |ui| {
                let frame = glass_frame(
                    Color32::from_rgba_unmultiplied(236, 243, 252, 30),
                    Color32::from_rgba_unmultiplied(255, 255, 255, 64),
                )
                .corner_radius(22.0)
                .shadow(egui::epaint::Shadow {
                    offset: [0, 10],
                    blur: 32,
                    spread: 0,
                    color: Color32::from_rgba_unmultiplied(0, 0, 0, 38),
                })
                .inner_margin(egui::Margin::symmetric(14, 14));

                frame.show(ui, |ui| {
                    ui.add_space(2.0);
                    ui.label(
                        RichText::new("surfaces")
                            .size(13.0)
                            .color(Color32::from_rgb(136, 156, 147)),
                    );
                    ui.add_space(8.0);

                    for tab in &self.tabs {
                        let selected = self.selected_tab_id == Some(tab.id());
                        let label = format!("{} {}", tab.kind_prefix(), tab.title());
                        let text = RichText::new(label).size(15.0).color(if selected {
                            Color32::from_rgb(236, 242, 238)
                        } else {
                            Color32::from_rgb(168, 184, 175)
                        });
                        let response = ui.add_sized(
                            [214.0, 32.0],
                            egui::Label::new(text).sense(egui::Sense::click()),
                        );
                        if selected {
                            let rect = response.rect.expand2(egui::vec2(8.0, 6.0));
                            ui.painter().rect_filled(
                                rect,
                                12.0,
                                Color32::from_rgba_unmultiplied(255, 255, 255, 28),
                            );
                            ui.painter().rect_stroke(
                                rect,
                                12.0,
                                egui::Stroke::new(
                                    1.0,
                                    Color32::from_rgba_unmultiplied(255, 255, 255, 82),
                                ),
                                egui::StrokeKind::Outside,
                            );
                            ui.painter().text(
                                response.rect.left_center(),
                                egui::Align2::LEFT_CENTER,
                                format!("{} {}", tab.kind_prefix(), tab.title()),
                                egui::FontId::proportional(15.0),
                                Color32::from_rgb(244, 247, 250),
                            );
                        }
                        if response.clicked() {
                            self.selected_tab_id = Some(tab.id());
                        }
                        ui.add_space(6.0);
                    }

                    ui.add_space(8.0);
                    ui.label(
                        RichText::new(format!("{} binds", self.binds.all().len()))
                            .size(12.0)
                            .color(Color32::from_rgb(113, 135, 124)),
                    );
                });
            });
    }

    fn show_workspace(&mut self, ctx: &egui::Context) {
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(Color32::TRANSPARENT))
            .show(ctx, |ui| {
                let window_rect = ui.max_rect().shrink(8.0);
                ui.painter().rect_filled(
                    window_rect,
                    28.0,
                    Color32::from_rgba_unmultiplied(8, 11, 16, 228),
                );
                ui.painter().rect_stroke(
                    window_rect,
                    28.0,
                    egui::Stroke::new(1.0, Color32::from_rgba_unmultiplied(255, 255, 255, 24)),
                    egui::StrokeKind::Outside,
                );

                ui.scope_builder(
                    egui::UiBuilder::new().max_rect(window_rect.shrink2(egui::vec2(14.0, 14.0))),
                    |ui| {
            ui.add_space(8.0);

            if self.tabs.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(120.0);
                    ui.heading("No tabs open");
                    ui.label("Use `osm` or `cmd+t`.");
                });
                return;
            }

            let selected_id = self
                .selected_tab_id
                .or_else(|| self.tabs.first().map(Tab::id));
            self.selected_tab_id = selected_id;

            if let Some(left_id) = self
                .left_split_id
                .filter(|left_id| *left_id != selected_id.unwrap_or(0))
            {
                let total_width = ui.available_width();
                let height = ui.available_height();
                let left_width = (total_width * 0.38).max(280.0);
                let right_width = (total_width - left_width - 10.0).max(280.0);

                ui.horizontal(|ui| {
                    ui.allocate_ui_with_layout(
                        Vec2::new(left_width, height),
                        egui::Layout::top_down(egui::Align::Min),
                        |ui| self.render_tab(ui, left_id),
                    );
                    ui.separator();
                    if let Some(selected_id) = selected_id {
                        ui.allocate_ui_with_layout(
                            Vec2::new(right_width, height),
                            egui::Layout::top_down(egui::Align::Min),
                            |ui| self.render_tab(ui, selected_id),
                        );
                    }
                });
            } else if let Some(selected_id) = selected_id {
                self.render_tab(ui, selected_id);
            }
                    },
                );
            });
    }

    fn render_tab(&mut self, ui: &mut egui::Ui, id: u64) {
        let Some(index) = self.tabs.iter().position(|tab| tab.id() == id) else {
            return;
        };

        let tab_title = self.tabs[index].title();
        let open_external =
            matches!(&self.tabs[index], Tab::Browser(browser) if browser.auto_open_external);
        glass_frame(
            Color32::from_rgba_unmultiplied(236, 243, 252, 10),
            Color32::from_rgba_unmultiplied(255, 255, 255, 22),
        )
        .corner_radius(22.0)
        .inner_margin(egui::Margin::symmetric(16, 16))
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.vertical(|ui| {
                ui.label(
                    RichText::new(tab_title)
                        .size(18.0)
                        .strong()
                        .color(Color32::from_rgb(221, 233, 225)),
                );
                ui.add_space(10.0);

                match &mut self.tabs[index] {
                    Tab::Terminal(terminal) => render_terminal(ui, terminal),
                    Tab::Editor(editor) => {
                        let response = ui.add_sized(
                            ui.available_size(),
                            egui::TextEdit::multiline(&mut editor.buffer)
                                .code_editor()
                                .desired_width(f32::INFINITY),
                        );
                        if response.changed() {
                            editor.dirty = true;
                        }
                    }
                    Tab::Browser(browser) => {
                        render_browser(ui, browser);
                    }
                }
            });
        });

        if open_external {
            self.open_browser_external(id);
            if let Some(Tab::Browser(browser)) = self.tabs.iter_mut().find(|tab| tab.id() == id) {
                browser.auto_open_external = false;
            }
        }
    }

    fn open_browser_external(&mut self, id: u64) {
        if let Some(Tab::Browser(browser)) = self.tabs.iter_mut().find(|tab| tab.id() == id) {
            match webbrowser::open(&browser.url) {
                Ok(_) => {
                    browser.status = format!("opened {} externally", browser.url);
                    self.status = browser.status.clone();
                }
                Err(error) => {
                    browser.status = format!("failed to open {}: {error}", browser.url);
                    self.status = browser.status.clone();
                }
            }
        }
    }
}

impl eframe::App for OsmApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        let _ = &self.server;
        self.drain_commands();
        self.handle_shortcuts(ctx);
        self.show_sidebar(ctx);
        self.show_workspace(ctx);
        self.draw_overlay_chrome(ctx);
        self.maybe_emit_startup_stats(ctx);
        ctx.request_repaint_after(Duration::from_millis(33));
    }

    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        self.binds.cleanup();
    }
}

impl Tab {
    fn id(&self) -> u64 {
        match self {
            Tab::Terminal(tab) => tab.id(),
            Tab::Editor(tab) => tab.id,
            Tab::Browser(tab) => tab.id,
        }
    }

    fn title(&self) -> String {
        match self {
            Tab::Terminal(tab) => tab.title(),
            Tab::Editor(tab) => editor_title(tab),
            Tab::Browser(tab) => browser_title(tab),
        }
    }

    fn kind_prefix(&self) -> &'static str {
        match self {
            Tab::Terminal(_) => "T",
            Tab::Editor(_) => "E",
            Tab::Browser(_) => "W",
        }
    }
}

fn editor_title(editor: &EditorTab) -> String {
    let file_name = editor
        .path
        .file_name()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| editor.path.display().to_string());
    if editor.dirty {
        format!("{file_name} *")
    } else {
        file_name
    }
}

fn browser_title(browser: &BrowserTab) -> String {
    browser
        .url
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .split('/')
        .next()
        .filter(|host| !host.is_empty())
        .unwrap_or(browser.url.as_str())
        .to_owned()
}

fn render_browser(ui: &mut egui::Ui, browser: &mut BrowserTab) {
    ui.label(
        RichText::new("browser handoff")
            .size(13.0)
            .color(Color32::from_rgb(136, 156, 147)),
    );
    ui.add_space(8.0);
    let response = ui.add_sized(
        [ui.available_width(), 28.0],
        egui::TextEdit::singleline(&mut browser.url),
    );
    if response.lost_focus() && ui.input(|input| input.key_pressed(egui::Key::Enter)) {
        browser.auto_open_external = true;
    }
    ui.add_space(8.0);
    ui.label(RichText::new(browser.status.clone()).color(Color32::from_rgb(144, 187, 169)));
    ui.add_space(18.0);
    ui.group(|ui| {
        ui.label("Use `osm web example.com` to create a browser tab.");
        ui.label("Press Enter in the URL field to hand the target to the OS browser.");
        ui.label("The shell is wired so an embedded webview backend can replace this handoff.");
    });
}

fn consume_shortcut(ctx: &egui::Context, modifiers: Modifiers, key: egui::Key) -> bool {
    ctx.input_mut(|input| input.consume_shortcut(&KeyboardShortcut::new(modifiers, key)))
}

fn spawn_bind(command: &str, cwd: &Path) {
    let command = command.to_owned();
    let cwd = cwd.to_path_buf();
    std::thread::spawn(move || {
        let _ = Command::new("/bin/sh")
            .arg("-lc")
            .arg(command)
            .current_dir(cwd)
            .spawn();
    });
}

fn configure_theme(ctx: &egui::Context) {
    configure_fonts(ctx);

    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = Vec2::new(10.0, 10.0);
    style.spacing.button_padding = Vec2::new(12.0, 8.0);
    style.text_styles.insert(
        egui::TextStyle::Heading,
        egui::FontId::new(24.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Body,
        egui::FontId::new(15.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Button,
        egui::FontId::new(14.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Monospace,
        egui::FontId::new(13.5, egui::FontFamily::Monospace),
    );
    style.text_styles.insert(
        egui::TextStyle::Small,
        egui::FontId::new(12.5, egui::FontFamily::Proportional),
    );
    style.visuals = egui::Visuals::dark();
    style.visuals.override_text_color = Some(Color32::from_rgb(224, 232, 227));
    style.visuals.panel_fill = Color32::from_rgb(11, 14, 18);
    style.visuals.window_fill = Color32::from_rgb(15, 20, 25);
    style.visuals.faint_bg_color = Color32::from_rgb(22, 28, 35);
    style.visuals.extreme_bg_color = Color32::from_rgb(10, 14, 18);
    style.visuals.widgets.noninteractive.bg_fill = Color32::from_rgb(18, 24, 29);
    style.visuals.widgets.inactive.bg_fill = Color32::from_rgb(18, 24, 29);
    style.visuals.widgets.hovered.bg_fill = Color32::from_rgb(27, 38, 44);
    style.visuals.widgets.active.bg_fill = Color32::from_rgb(57, 89, 77);
    style.visuals.selection.bg_fill = Color32::from_rgb(65, 102, 88);
    style.visuals.hyperlink_color = Color32::from_rgb(121, 200, 171);
    ctx.set_style(style);
}

fn exit_after_from_env() -> Option<Duration> {
    let raw = std::env::var("OSMIUM_EXIT_AFTER_MS").ok()?;
    let millis = raw.parse::<u64>().ok()?;
    Some(Duration::from_millis(millis))
}

fn configure_fonts(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();

    if let Some(sf_pro) = load_font("/System/Library/Fonts/SFNS.ttf") {
        fonts.font_data.insert(
            "sf-pro".into(),
            std::sync::Arc::new(egui::FontData::from_owned(sf_pro)),
        );
        if let Some(family) = fonts.families.get_mut(&egui::FontFamily::Proportional) {
            family.insert(0, "sf-pro".into());
        }
    }

    if let Some(sf_mono) = load_font("/System/Library/Fonts/SFNSMono.ttf") {
        fonts.font_data.insert(
            "sf-mono".into(),
            std::sync::Arc::new(egui::FontData::from_owned(sf_mono)),
        );
        if let Some(family) = fonts.families.get_mut(&egui::FontFamily::Monospace) {
            family.insert(0, "sf-mono".into());
        }
    }

    ctx.set_fonts(fonts);
}

fn load_font(path: &str) -> Option<Vec<u8>> {
    fs::read(path).ok()
}

fn glass_frame(fill: Color32, stroke: Color32) -> egui::Frame {
    egui::Frame::new()
        .fill(fill)
        .stroke(egui::Stroke::new(1.0, stroke))
        .corner_radius(18.0)
}
