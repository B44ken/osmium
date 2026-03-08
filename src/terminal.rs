use std::env;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;

use anyhow::{Context, Result};
use eframe::egui::{self, Key, Modifiers};
use parking_lot::Mutex;
use portable_pty::{CommandBuilder, MasterPty, PtySize, native_pty_system};
use vt100::Parser;

pub struct TerminalTab {
    id: u64,
    title: String,
    cwd: PathBuf,
    parser: Arc<Mutex<Parser>>,
    writer: Arc<Mutex<Box<dyn Write + Send>>>,
    master: Box<dyn MasterPty + Send>,
    child: Box<dyn portable_pty::Child + Send + Sync>,
    cols: u16,
    rows: u16,
}

impl TerminalTab {
    pub fn spawn(id: u64, cwd: PathBuf) -> Result<Self> {
        let pty_system = native_pty_system();
        let cols = 120;
        let rows = 36;
        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .context("failed to create PTY")?;

        let shell = env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_owned());
        let mut command = CommandBuilder::new(shell);
        command.arg("-i");
        command.cwd(cwd.clone());

        let child = pair
            .slave
            .spawn_command(command)
            .context("failed to spawn shell")?;
        let mut reader = pair
            .master
            .try_clone_reader()
            .context("failed to clone PTY reader")?;
        let writer = pair
            .master
            .take_writer()
            .context("failed to create PTY writer")?;
        let parser = Arc::new(Mutex::new(Parser::new(rows, cols, 5_000)));
        let parser_reader = parser.clone();

        thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(size) => parser_reader.lock().process(&buffer[..size]),
                    Err(_) => break,
                }
            }
        });

        Ok(Self {
            id,
            title: format!("term:{}", cwd.display()),
            cwd,
            parser,
            writer: Arc::new(Mutex::new(writer)),
            master: pair.master,
            child,
            cols,
            rows,
        })
    }

    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn title(&self) -> String {
        self.cwd
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| self.title.clone())
    }

    pub fn contents(&self) -> String {
        self.parser.lock().screen().contents()
    }

    pub fn resize_to_ui(&mut self, width_px: f32, height_px: f32) {
        let cols = (width_px / 8.4).max(40.0) as u16;
        let rows = (height_px / 18.0).max(12.0) as u16;
        if cols == self.cols && rows == self.rows {
            return;
        }

        if self
            .master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: width_px.max(0.0) as u16,
                pixel_height: height_px.max(0.0) as u16,
            })
            .is_ok()
        {
            self.cols = cols;
            self.rows = rows;
            self.parser.lock().set_size(rows, cols);
        }
    }

    pub fn send_text(&self, text: &str) {
        let mut writer = self.writer.lock();
        let _ = writer.write_all(text.as_bytes());
        let _ = writer.flush();
    }

    pub fn handle_key(&self, key: Key, modifiers: Modifiers) -> bool {
        if modifiers.ctrl {
            if let Some(code) = ctrl_code(key) {
                let mut writer = self.writer.lock();
                let _ = writer.write_all(&[code]);
                let _ = writer.flush();
                return true;
            }
        }

        let sequence = match key {
            Key::Enter => Some("\r"),
            Key::Tab if modifiers.shift => Some("\u{1b}[Z"),
            Key::Tab => Some("\t"),
            Key::Backspace => Some("\u{7f}"),
            Key::ArrowUp => Some("\u{1b}[A"),
            Key::ArrowDown => Some("\u{1b}[B"),
            Key::ArrowRight => Some("\u{1b}[C"),
            Key::ArrowLeft => Some("\u{1b}[D"),
            Key::Home => Some("\u{1b}[H"),
            Key::End => Some("\u{1b}[F"),
            Key::Delete => Some("\u{1b}[3~"),
            Key::Escape => Some("\u{1b}"),
            _ => None,
        };

        if let Some(sequence) = sequence {
            let mut writer = self.writer.lock();
            let _ = writer.write_all(sequence.as_bytes());
            let _ = writer.flush();
            return true;
        }

        false
    }
}

impl Drop for TerminalTab {
    fn drop(&mut self) {
        let _ = self.child.kill();
    }
}

fn ctrl_code(key: Key) -> Option<u8> {
    match key {
        Key::A => Some(0x01),
        Key::B => Some(0x02),
        Key::C => Some(0x03),
        Key::D => Some(0x04),
        Key::E => Some(0x05),
        Key::F => Some(0x06),
        Key::G => Some(0x07),
        Key::H => Some(0x08),
        Key::I => Some(0x09),
        Key::J => Some(0x0a),
        Key::K => Some(0x0b),
        Key::L => Some(0x0c),
        Key::M => Some(0x0d),
        Key::N => Some(0x0e),
        Key::O => Some(0x0f),
        Key::P => Some(0x10),
        Key::Q => Some(0x11),
        Key::R => Some(0x12),
        Key::S => Some(0x13),
        Key::T => Some(0x14),
        Key::U => Some(0x15),
        Key::V => Some(0x16),
        Key::W => Some(0x17),
        Key::X => Some(0x18),
        Key::Y => Some(0x19),
        Key::Z => Some(0x1a),
        _ => None,
    }
}

pub fn render_terminal(ui: &mut egui::Ui, terminal: &mut TerminalTab) {
    let available = ui.available_size();
    terminal.resize_to_ui(available.x, available.y);

    egui::ScrollArea::vertical()
        .stick_to_bottom(true)
        .auto_shrink([false, false])
        .show(ui, |ui| {
            ui.add(
                egui::Label::new(
                    egui::RichText::new(terminal.contents())
                        .monospace()
                        .size(13.0),
                )
                .sense(egui::Sense::click()),
            );
        });
}
