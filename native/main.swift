import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Darwin
import Foundation
import SwiftTerm
import WebKit

// MARK: - Extensions

extension NSView {
    func pin(to p: NSView, insets i: NSEdgeInsets = .init()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: p.leadingAnchor, constant: i.left),
            trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -i.right),
            topAnchor.constraint(equalTo: p.topAnchor, constant: i.top),
            bottomAnchor.constraint(equalTo: p.bottomAnchor, constant: -i.bottom),
        ])
    }
}

extension NSVisualEffectView {
    func glass(_ mat: Material = .hudWindow, blend: BlendingMode = .withinWindow,
               radius: CGFloat = 14, border: NSColor? = nil, bg: NSColor? = nil) {
        material = mat; blendingMode = blend; state = .active; wantsLayer = true
        layer?.cornerRadius = radius; layer?.masksToBounds = true
        if let border { layer?.borderWidth = 1; layer?.borderColor = border.cgColor }
        if let bg { layer?.backgroundColor = bg.cgColor }
        if #available(macOS 13.0, *) { layer?.cornerCurve = .continuous }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

func appColor(_ hex: String, alpha: CGFloat = 1.0) -> NSColor {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var v: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&v)
    if cleaned.count > 6 {
        return NSColor(calibratedRed: CGFloat((v >> 24) & 0xFF) / 255,
                       green: CGFloat((v >> 16) & 0xFF) / 255, blue: CGFloat((v >> 8) & 0xFF) / 255,
                       alpha: CGFloat(v & 0xFF) / 255)
    }
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

func animate(_ dur: Double = 0.15, body: @escaping @MainActor () -> Void) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = dur; ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ctx.allowsImplicitAnimation = true; body()
    }
}

// MARK: - Types

struct AppCommand: Decodable, Sendable {
    let type: String
    let cwd: String?
    let path: String?
    let url: String?
    let event: String?
    let command: String?
}

struct SaveBind {
    let event: String
    let command: String
}

// MARK: - Config

final class Cfg: Sendable {
    static let shared = Cfg()
    private let data: [String: String]

    init() {
        var d: [String: String] = [:]
        let path = NSHomeDirectory() + "/.osm/config"
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                d[String(line[line.startIndex..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        data = d
    }

    func string(_ key: String) -> String { data[key]! }
    func float(_ key: String) -> CGFloat { CGFloat(Double(data[key]!)!) }
    func color(_ key: String) -> NSColor { appColor(data[key]!) }
}

let cfg = Cfg.shared

extension Cfg {
    var font: NSFont {
        let s = float("options.font"), n = string("options.font_face")
        return NSFont(name: n, size: s) ?? .monospacedSystemFont(ofSize: s, weight: .regular)
    }
    func font(_ w: NSFont.Weight) -> NSFont {
        let s = float("options.font"), n = string("options.font_face")
        return NSFont(name: n, size: s) ?? .monospacedSystemFont(ofSize: s, weight: w)
    }
    var editorTheme: EditorTheme {
        func a(_ key: String, bold: Bool = false) -> EditorTheme.Attribute {
            EditorTheme.Attribute(color: color(key), bold: bold)
        }
        return EditorTheme(
            text: a("theme.editor_text"), insertionPoint: color("theme.editor_cursor"),
            invisibles: a("theme.editor_invisibles"), background: color("theme.editor_bg"),
            lineHighlight: color("theme.editor_line_highlight"), selection: color("theme.editor_selection"),
            keywords: a("theme.editor_keywords", bold: true), commands: a("theme.editor_commands"),
            types: a("theme.editor_types"), attributes: a("theme.editor_attributes"),
            variables: a("theme.editor_variables"), values: a("theme.editor_values"),
            numbers: a("theme.editor_numbers"), strings: a("theme.editor_strings"),
            characters: a("theme.editor_characters"), comments: a("theme.editor_comments")
        )
    }
}

// MARK: - Surfaces

@MainActor
class Surface: NSViewController {
    let tabID = UUID()
    let kindPrefix: String
    var titleText: String { "surface" }
    var preferredFirstResponder: NSResponder? { view }
    var onStateChange: (() -> Void)?
    var onRequestClose: ((String?) -> Void)?

    init(kindPrefix: String) {
        self.kindPrefix = kindPrefix
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    func save(binds: [SaveBind]) -> String? { nil }
    func activate(in window: NSWindow?) {
        guard let r = preferredFirstResponder else { return }
        window?.makeFirstResponder(r)
    }
    func makeRoot() -> NSView {
        let root = NSView(); root.wantsLayer = true; view = root; return root
    }
}

final class TerminalSurface: Surface, @preconcurrency LocalProcessTerminalViewDelegate {
    private let terminalView = LocalProcessTerminalView(frame: .zero)
    private let initialDirectory: String
    private var currentDirectory: String
    private var started = false

    override var titleText: String { URL(fileURLWithPath: currentDirectory).lastPathComponent.ifEmpty(currentDirectory) }
    override var preferredFirstResponder: NSResponder? { terminalView }
    var cwd: String { currentDirectory }

    init(cwd: String) {
        initialDirectory = cwd; currentDirectory = cwd
        super.init(kindPrefix: "T")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = makeRoot()
        terminalView.processDelegate = self
        terminalView.optionAsMetaKey = true
        terminalView.nativeForegroundColor = cfg.color("theme.terminal_foreground")
        terminalView.nativeBackgroundColor = cfg.color("theme.terminal_bg")
        terminalView.caretColor = cfg.color("theme.terminal_cursor")
        terminalView.font = cfg.font
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
        root.wantsLayer = true
        root.layer?.backgroundColor = cfg.color("theme.terminal_bg").cgColor
        root.addSubview(terminalView)
        terminalView.pin(to: root, insets: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
    }

    override func activate(in window: NSWindow?) {
        if !started {
            started = true
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            terminalView.startProcess(executable: shell, args: ["-l"],
                execName: "-\(URL(fileURLWithPath: shell).lastPathComponent)", currentDirectory: initialDirectory)
        }
        window?.makeFirstResponder(terminalView)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        currentDirectory = directory; onStateChange?()
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let msg = exitCode.map { $0 == 0 ? "terminal exited" : "terminal exited (\($0))" } ?? "terminal exited"
        DispatchQueue.main.async { [weak self] in self?.onRequestClose?(msg) }
    }
}

final class EditorSurface: Surface {
    private let filePath: String
    private let editorController: TextViewController
    private var dirty = false

    override var titleText: String {
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        return dirty ? "\(name) *" : name
    }
    override var preferredFirstResponder: NSResponder? { editorController.textView }
    var currentPath: String { filePath }

    init(path: String) {
        filePath = path
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let url = URL(fileURLWithPath: path)
        let lang = CodeLanguage.detectLanguageFrom(url: url,
            prefixBuffer: String(source.prefix(4096)), suffixBuffer: String(source.suffix(2048)))
        editorController = TextViewController(string: source, language: lang,
            configuration: Self.editorConfig(), cursorPositions: [],
            highlightProviders: [TreeSitterClient()],
            undoManager: CEUndoManager())
        super.init(kindPrefix: "E")
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func loadView() {
        let root = makeRoot()
        addChild(editorController)
        root.addSubview(editorController.view)
        editorController.view.pin(to: root)
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange),
            name: TextView.textDidChangeNotification, object: editorController.textView)
    }

    override func activate(in window: NSWindow?) { window?.makeFirstResponder(editorController.textView) }

    override func save(binds: [SaveBind]) -> String? {
        let url = URL(fileURLWithPath: filePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try editorController.text.write(to: url, atomically: true, encoding: .utf8)
            dirty = false; onStateChange?()
            let matching = binds.filter { $0.event == "save:\(filePath)" || $0.event == "save:\(url.lastPathComponent)" }
            for bind in matching {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-lc", bind.command]; p.currentDirectoryURL = url.deletingLastPathComponent()
                try? p.run()
            }
            if let last = matching.last { return "saved \(url.lastPathComponent) and ran `\(last.command)`" }
            return "saved \(url.lastPathComponent)"
        } catch { return "save failed: \(error.localizedDescription)" }
    }

    func matches(path: String) -> Bool { currentPath == path }
    @objc private func textDidChange() { dirty = true; onStateChange?() }

    private static func editorConfig() -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(theme: cfg.editorTheme, useThemeBackground: true, font: cfg.font(.regular),
                lineHeightMultiple: 1.15, letterSpacing: 1.0, wrapLines: false, useSystemCursor: true,
                tabWidth: 4, bracketPairEmphasis: .flash),
            behavior: .init(isEditable: true, isSelectable: true,
                indentOption: .spaces(count: 4), reformatAtColumn: 100),
            layout: .init(editorOverscroll: 0.08,
                contentInsets: NSEdgeInsets(top: 12, left: 0, bottom: 20, right: 0),
                additionalTextInsets: NSEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)),
            peripherals: .init(showGutter: true, showMinimap: false, showReformattingGuide: false,
                showFoldingRibbon: false, invisibleCharactersConfiguration: .empty, warningCharacters: [])
        )
    }
}

final class BrowserSurface: Surface, WKNavigationDelegate {
    private let webView = WKWebView(frame: .zero)
    private var currentURL: URL

    override var titleText: String { currentURL.host ?? currentURL.absoluteString }
    override var preferredFirstResponder: NSResponder? { webView }

    init(url: URL) { currentURL = url; super.init(kindPrefix: "W") }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = makeRoot()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        root.addSubview(webView)
        webView.pin(to: root)
        webView.load(URLRequest(url: currentURL))
    }

    override func activate(in window: NSWindow?) { window?.makeFirstResponder(webView) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { currentURL = url; onStateChange?() }
    }
}

// MARK: - Main Controller

final class MainController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var tabs: [Surface] = []
    private var selectedTabID: UUID?
    private var saveBinds: [SaveBind] = []
    private var sidebarShown = false
    private var paletteVisible = false
    private var displayedSurfaceID: UUID?
    private var currentPanel: GlassPanel?

    private let ci: CGFloat = 8
    private let sidebarExpanded: CGFloat = 216
    private let sidebarCollapsed: CGFloat = 84

    private let windowGlass = NSVisualEffectView()
    private let contentContainer = NSView()
    private let sidebar = NSVisualEffectView()
    private let tableView = NSTableView()
    private let sidebarScroll = NSScrollView()
    private let palette = NSVisualEffectView()
    private var sidebarLeading: NSLayoutConstraint?
    private var sidebarWidth: NSLayoutConstraint?
    private var center: NSLayoutConstraint?

    private var syncingSelection = false

    var hasTabs: Bool { !tabs.isEmpty }

    override func loadView() {
        view = NSView(); view.wantsLayer = true
        setupGlass(); setupContent(); setupSidebar(); setupPalette()
    }

    override func viewDidAppear() { super.viewDidAppear(); updateTitle() }

    // MARK: IPC

    func apply(_ cmd: AppCommand) {
        switch cmd.type {
        case "open-terminal":
            install(TerminalSurface(cwd: cmd.cwd ?? FileManager.default.currentDirectoryPath))
        case "open-editor":
            guard let path = cmd.path else { return }
            openEditor(path: path)
        case "open-browser":
            guard let raw = cmd.url, let url = URL(string: raw) else { return }
            install(BrowserSurface(url: url))
        case "add-bind":
            guard let event = cmd.event, let command = cmd.command else { return }
            saveBinds.append(SaveBind(event: event, command: command))
        default: break
        }
    }

    // MARK: Shortcuts

    func handleModifierFlags(_ flags: NSEvent.ModifierFlags) {
        showSidebar(flags.intersection([.shift, .control, .option, .command]) == .option)
    }

    func handleShortcut(event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods == .control && key == "q" || mods == .command && key == "q" { NSApp.terminate(nil); return true }
        if paletteVisible { return handlePaletteKey(key) }
        if mods == .command && key == "t" { presentPalette(); return true }
        if mods == .command && key == "w" { closeSelectedTab(); return true }
        if mods == .command && key == "s" { saveEditor(); return true }
        if mods == .option && key == "[" { cycleTabs(-1); return true }
        if mods == .option && key == "]" { cycleTabs(1); return true }
        return false
    }

    // MARK: Tab management

    private func openEditor(path: String) {
        if let existing = tabs.compactMap({ $0 as? EditorSurface }).first(where: { $0.matches(path: path) }) {
            selectedTabID = existing.tabID; renderTabs(); return
        }
        install(EditorSurface(path: path))
    }

    private func install(_ surface: Surface) {
        addChild(surface)
        surface.onStateChange = { [weak self] in self?.renderTabs() }
        surface.onRequestClose = { [weak self, weak surface] _ in
            guard let self, let surface else { return }
            self.closeTab(surface.tabID)
        }
        tabs.append(surface); selectedTabID = surface.tabID; renderTabs()
    }

    private func cycleTabs(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        let i = tabs.firstIndex(where: { $0.tabID == selectedTabID }) ?? 0
        selectedTabID = tabs[(i + delta + tabs.count) % tabs.count].tabID; renderTabs()
    }

    private func closeSelectedTab() {
        guard let id = selectedTabID else { return }
        closeTab(id)
    }

    private func closeTab(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.tabID == id }) else { return }
        let surface = tabs.remove(at: i)
        if selectedTabID == id { selectedTabID = tabs.indices.contains(i) ? tabs[i].tabID : tabs.last?.tabID }
        surface.removeFromParent(); renderTabs()
    }

    private func saveEditor() {
        guard let editor = selected() as? EditorSurface else { return }
        _ = editor.save(binds: saveBinds)
        renderTabs()
    }

    private func selected() -> Surface? { tabs.first { $0.tabID == selectedTabID } }

    private func workingDirectory() -> String {
        if let t = selected() as? TerminalSurface { return t.cwd }
        if let e = selected() as? EditorSurface { return URL(fileURLWithPath: e.currentPath).deletingLastPathComponent().path }
        return FileManager.default.currentDirectoryPath
    }

    // MARK: Render

    private func renderTabs() {
        let surface = selected()
        if surface?.tabID != displayedSurfaceID {
            displayedSurfaceID = surface?.tabID
            currentPanel?.removeFromSuperview()
            currentPanel = nil
            if let surface {
                let panel = GlassPanel()
                panel.contentView = surface.view
                contentContainer.addSubview(panel)
                panel.pin(to: contentContainer)
                currentPanel = panel
                surface.activate(in: view.window)
            }
            tableView.reloadData()
        } else {
            for row in 0..<tabs.count {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TabCell else { continue }
                cell.configure(text: "\(tabs[row].kindPrefix) \(tabs[row].titleText)", selected: tabs[row].tabID == selectedTabID)
            }
        }
        syncTableSelection(); updateTitle()
    }

    private func syncTableSelection() {
        guard let id = selectedTabID, let row = tabs.firstIndex(where: { $0.tabID == id }) else {
            tableView.deselectAll(nil); return
        }
        guard tableView.selectedRow != row else { return }
        syncingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        syncingSelection = false
    }

    private func updateTitle() {
        view.window?.title = selected().map { "osmium   \($0.kindPrefix) \($0.titleText)" } ?? "osmium"
    }

    func focusSurface(attempt: Int = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.view.window, let s = self.selected() else { return }
            s.activate(in: w)
            if let r = s.preferredFirstResponder, !(w.firstResponder === r), attempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focusSurface(attempt: attempt + 1) }
            }
        }
    }

    // MARK: Sidebar

    private func showSidebar(_ visible: Bool) {
        guard sidebarShown != visible else { return }
        sidebarShown = visible
        sidebarLeading?.constant = visible ? ci : -sidebarCollapsed - ci
        sidebarWidth?.constant = visible ? sidebarExpanded : sidebarCollapsed
        animate(body: { [self] in view.layoutSubtreeIfNeeded() })
    }

    // MARK: Create palette

    private func handlePaletteKey(_ key: String) -> Bool {
        switch key {
        case "1": dismissPalette(); install(TerminalSurface(cwd: workingDirectory()))
        case "2": dismissPalette(); openEditorFromPicker()
        case "\u{1b}": dismissPalette()
        default: break
        }
        return true
    }

    private func presentPalette() {
        guard !paletteVisible else { return }
        paletteVisible = true; center?.constant = 12
        palette.isHidden = false; palette.alphaValue = 0
        view.window?.makeFirstResponder(nil)
        animate(body: { [self] in
            palette.animator().alphaValue = 1; center?.animator().constant = 0
            view.layoutSubtreeIfNeeded()
        })
    }

    private func dismissPalette() {
        guard paletteVisible else { return }
        paletteVisible = false; center?.constant = 12
        animate(body: { [self] in palette.animator().alphaValue = 0; view.layoutSubtreeIfNeeded() })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.palette.isHidden = true; self?.focusSurface()
        }
    }

    private func openEditorFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory())
        guard let window = view.window else {
            if panel.runModal() == .OK, let url = panel.url { openEditor(path: url.path) }
            return
        }
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url else { self?.focusSurface(); return }
            self?.openEditor(path: url.path)
        }
    }

    // MARK: Table view

    func numberOfRows(in tableView: NSTableView) -> Int { tabs.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 34 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TabCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? TabCell) ?? TabCell(frame: .zero)
        cell.identifier = id
        let item = tabs[row]
        cell.configure(text: "\(item.kindPrefix) \(item.titleText)", selected: item.tabID == selectedTabID)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < tabs.count else { return }
        selectedTabID = tabs[row].tabID; renderTabs()
    }

    // MARK: Layout setup

    private func setupGlass() {
        windowGlass.glass(.underWindowBackground, blend: .behindWindow, radius: 16, bg: cfg.color("theme.shell_bg"))
        view.addSubview(windowGlass)
        windowGlass.pin(to: view)
    }

    private func setupContent() {
        windowGlass.addSubview(contentContainer)
        contentContainer.pin(to: windowGlass, insets: NSEdgeInsets(top: ci, left: ci, bottom: ci, right: ci))
    }

    private func setupSidebar() {
        sidebar.glass(.sidebar, radius: 16, border: cfg.color("theme.sidebar_stroke"), bg: cfg.color("theme.sidebar_fill"))
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        windowGlass.addSubview(sidebar, positioned: .above, relativeTo: contentContainer)

        tableView.headerView = nil; tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none; tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.rowHeight = 34
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tab"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col); tableView.delegate = self; tableView.dataSource = self

        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.borderType = .noBorder; sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true; sidebarScroll.scrollerStyle = .overlay
        sidebarScroll.documentView = tableView
        sidebar.addSubview(sidebarScroll)

        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: windowGlass.leadingAnchor, constant: -sidebarCollapsed - ci)
        sidebarLeading?.isActive = true
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: sidebarCollapsed)
        sidebarWidth?.isActive = true
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: windowGlass.topAnchor, constant: ci),
            sidebar.bottomAnchor.constraint(equalTo: windowGlass.bottomAnchor, constant: -ci),
        ])
        sidebarScroll.pin(to: sidebar, insets: NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
    }

    private func setupPalette() {
        palette.glass(radius: 14, border: cfg.color("theme.panel_border"), bg: NSColor.black.withAlphaComponent(0.18))
        palette.translatesAutoresizingMaskIntoConstraints = false
        palette.alphaValue = 0; palette.isHidden = true
        windowGlass.addSubview(palette, positioned: .above, relativeTo: sidebar)

        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        palette.addSubview(stack)

        let title = NSTextField(labelWithString: "new surface")
        title.font = .systemFont(ofSize: 14, weight: .semibold); title.textColor = cfg.color("theme.overlay_text")

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(paletteRow("1", "terminal"))
        stack.addArrangedSubview(paletteRow("2", "editor"))

        center = palette.centerYAnchor.constraint(equalTo: windowGlass.centerYAnchor)
        NSLayoutConstraint.activate([
            center!,
            palette.centerXAnchor.constraint(equalTo: windowGlass.centerXAnchor),
            palette.widthAnchor.constraint(equalToConstant: 200),
        ])
        stack.pin(to: palette, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
    }

    private func paletteRow(_ key: String, _ title: String) -> NSView {
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
        let k = NSTextField(labelWithString: key)
        k.font = cfg.font(.medium); k.textColor = cfg.color("theme.overlay_text")
        k.setContentHuggingPriority(.required, for: .horizontal)
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .medium); t.textColor = cfg.color("theme.overlay_subdued")
        row.addArrangedSubview(k); row.addArrangedSubview(t)
        return row
    }

}

// MARK: - Views

final class GlassPanel: NSVisualEffectView {
    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let v = contentView else { return }
            addSubview(v); v.pin(to: self)
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        glass(radius: 14, border: cfg.color("theme.panel_border"), bg: cfg.color("theme.panel_bg"))
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class TabCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let highlight = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        highlight.glass(.selection, radius: 10); highlight.alphaValue = 0
        addSubview(highlight)
        highlight.pin(to: self, insets: NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        textField = label
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(text: String, selected: Bool) {
        label.stringValue = text
        label.textColor = selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_subdued")
        highlight.alphaValue = selected ? 1 : 0
    }
}

final class ShellWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Command Server

final class CommandServer: @unchecked Sendable {
    private let socketURL: URL
    private let handler: @MainActor @Sendable (AppCommand) -> Void
    private var fd: Int32 = -1
    private var running = false

    init(socketURL: URL, handler: @escaping @MainActor @Sendable (AppCommand) -> Void) {
        self.socketURL = socketURL; self.handler = handler
    }

    func start() throws {
        try? FileManager.default.removeItem(at: socketURL)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketURL.path.utf8CString
        pathBytes.withUnsafeBufferPointer { buf in
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dest in
                    _ = memcpy(dest, buf.baseAddress!, min(buf.count, maxLen))
                }
            }
        }
        let len = socklen_t(MemoryLayout<sa_family_t>.size + socketURL.path.utf8.count + 1)
        let result = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, len) } }
        guard result == 0 else { let e = errno; close(fd); fd = -1; throw NSError(domain: NSPOSIXErrorDomain, code: Int(e)) }
        guard listen(fd, 16) == 0 else { let e = errno; close(fd); fd = -1; throw NSError(domain: NSPOSIXErrorDomain, code: Int(e)) }
        running = true; Thread { [weak self] in self?.acceptLoop() }.start()
    }

    func stop() {
        running = false; if fd >= 0 { close(fd); fd = -1 }
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptLoop() {
        while running {
            let client = accept(fd, nil, nil)
            if client < 0 { if errno == EINTR || errno == EAGAIN { continue }; usleep(40_000); continue }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while true { let n = read(client, &buf, buf.count); if n > 0 { data.append(buf, count: n) } else { break } }
            close(client)
            guard let payload = String(data: data, encoding: .utf8) else { continue }
            for line in payload.split(separator: "\n") {
                guard let d = line.data(using: .utf8) else { continue }
                do { let cmd = try JSONDecoder().decode(AppCommand.self, from: d); let h = handler; Task { @MainActor in h(cmd) } }
                catch { fputs("osmium: \(error)\n", stderr) }
            }
        }
    }
}

// MARK: - App Delegate

final class App: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var server: CommandServer?
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var controller: MainController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appSub = NSMenu()
        appSub.addItem(NSMenuItem(title: "Quit osmium", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appSub

        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editSub = NSMenu(title: "Edit")
        editSub.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editSub.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editSub.addItem(.separator())
        editSub.addItem(NSMenuItem(title: "Cut", action: Selector(("cut:")), keyEquivalent: "x"))
        editSub.addItem(NSMenuItem(title: "Copy", action: Selector(("copy:")), keyEquivalent: "c"))
        editSub.addItem(NSMenuItem(title: "Paste", action: Selector(("paste:")), keyEquivalent: "v"))
        editSub.addItem(NSMenuItem(title: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a"))
        editItem.submenu = editSub

        NSApp.mainMenu = menu

        let osmDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".osm", isDirectory: true)
        try? FileManager.default.createDirectory(at: osmDir, withIntermediateDirectories: true)

        let mc = MainController(); controller = mc
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let ww = min(max(v.width * 0.86, 1180), 1680), hh = min(max(v.height * 0.88, 760), 1120)
        let w = ShellWindow(contentRect: NSRect(x: v.midX - ww/2, y: v.midY - hh/2, width: ww, height: hh),
            styleMask: [.borderless, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = true
        w.titlebarAppearsTransparent = true; w.isMovableByWindowBackground = false
        w.collectionBehavior = [.fullScreenNone]; w.minSize = NSSize(width: 1180, height: 760)
        w.contentViewController = mc; w.center(); w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); window = w

        let srv = CommandServer(socketURL: osmDir.appendingPathComponent("osmium.sock")) { [weak self] cmd in self?.controller?.apply(cmd) }
        do { try srv.start(); server = srv } catch { fputs("osmium socket failed: \(error)\n", stderr) }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.controller?.handleModifierFlags(e.modifierFlags); return e
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            (self?.controller?.handleShortcut(event: e) == true) ? nil : e
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let mc = self?.controller, !mc.hasTabs else { return }
            mc.apply(AppCommand(type: "open-terminal", cwd: FileManager.default.currentDirectoryPath, path: nil, url: nil, event: nil, command: nil))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller?.focusSurface() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { controller?.focusSurface() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        server?.stop()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = App()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
