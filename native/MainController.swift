import AppKit
import Foundation

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
        view = NSView()
        view.wantsLayer = true
        setupGlass()
        setupContent()
        setupSidebar()
        setupPalette()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateTitle()
    }

    func apply(_ cmd: AppCommand) {
        switch cmd.type {
        case "open-terminal":
            install(TerminalSurface(cwd: cmd.cwd ?? FileManager.default.currentDirectoryPath))
        case "open-agent":
            openAgent(cwd: cmd.cwd ?? workingDirectory())
        case "open-editor":
            guard let path = cmd.path else { return }
            openEditor(path: path)
        case "open-browser":
            guard let raw = cmd.url, let url = URL(string: raw) else { return }
            install(BrowserSurface(url: url))
        case "add-bind":
            guard let event = cmd.event, let command = cmd.command else { return }
            saveBinds.append(SaveBind(event: event, command: command))
        default:
            break
        }
    }

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

    private func openEditor(path: String) {
        if let existing = tabs.compactMap({ $0 as? EditorSurface }).first(where: { $0.matches(path: path) }) {
            selectedTabID = existing.tabID
            renderTabs()
            return
        }
        install(EditorSurface(path: path))
    }

    private func openAgent(cwd: String) {
        if let existing = tabs.compactMap({ $0 as? AgentSurface }).first(where: { $0.cwd == cwd }) {
            selectedTabID = existing.tabID
            renderTabs()
            return
        }
        install(AgentSurface(cwd: cwd))
    }

    private func install(_ surface: Surface) {
        addChild(surface)
        surface.onStateChange = { [weak self] in self?.renderTabs() }
        surface.onRequestClose = { [weak self, weak surface] _ in
            guard let self, let surface else { return }
            self.closeTab(surface.tabID)
        }
        tabs.append(surface)
        selectedTabID = surface.tabID
        renderTabs()
    }

    private func cycleTabs(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        let i = tabs.firstIndex(where: { $0.tabID == selectedTabID }) ?? 0
        selectedTabID = tabs[(i + delta + tabs.count) % tabs.count].tabID
        renderTabs()
    }

    private func closeSelectedTab() {
        guard let id = selectedTabID else { return }
        closeTab(id)
    }

    private func closeTab(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.tabID == id }) else { return }
        let surface = tabs.remove(at: i)
        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(i) ? tabs[i].tabID : tabs.last?.tabID
        }
        surface.removeFromParent()
        renderTabs()
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
        if let a = selected() as? AgentSurface { return a.cwd }
        return FileManager.default.currentDirectoryPath
    }

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
        syncTableSelection()
        updateTitle()
    }

    private func syncTableSelection() {
        guard let id = selectedTabID, let row = tabs.firstIndex(where: { $0.tabID == id }) else {
            tableView.deselectAll(nil)
            return
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.focusSurface(attempt: attempt + 1)
                }
            }
        }
    }

    private func showSidebar(_ visible: Bool) {
        guard sidebarShown != visible else { return }
        sidebarShown = visible
        sidebarLeading?.constant = visible ? ci : -sidebarCollapsed - ci
        sidebarWidth?.constant = visible ? sidebarExpanded : sidebarCollapsed
        animate {
            self.view.layoutSubtreeIfNeeded()
        }
    }

    private func handlePaletteKey(_ key: String) -> Bool {
        switch key {
        case "1":
            dismissPalette()
            install(TerminalSurface(cwd: workingDirectory()))
        case "2":
            dismissPalette()
            openEditorFromPicker()
        case "3":
            dismissPalette()
            openAgent(cwd: workingDirectory())
        case "\u{1b}":
            dismissPalette()
        default:
            break
        }
        return true
    }

    private func presentPalette() {
        guard !paletteVisible else { return }
        paletteVisible = true
        center?.constant = 12
        palette.isHidden = false
        palette.alphaValue = 0
        view.window?.makeFirstResponder(nil)
        animate {
            self.palette.animator().alphaValue = 1
            self.center?.animator().constant = 0
            self.view.layoutSubtreeIfNeeded()
        }
    }

    private func dismissPalette() {
        guard paletteVisible else { return }
        paletteVisible = false
        center?.constant = 12
        animate {
            self.palette.animator().alphaValue = 0
            self.view.layoutSubtreeIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.palette.isHidden = true
            self?.focusSurface()
        }
    }

    private func openEditorFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory())
        guard let window = view.window else {
            if panel.runModal() == .OK, let url = panel.url {
                openEditor(path: url.path)
            }
            return
        }
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url else {
                self?.focusSurface()
                return
            }
            self?.openEditor(path: url.path)
        }
    }

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
        selectedTabID = tabs[row].tabID
        renderTabs()
    }

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

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.rowHeight = 34
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tab"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.delegate = self
        tableView.dataSource = self

        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.borderType = .noBorder
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.scrollerStyle = .overlay
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
        palette.alphaValue = 0
        palette.isHidden = true
        windowGlass.addSubview(palette, positioned: .above, relativeTo: sidebar)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        palette.addSubview(stack)

        let title = NSTextField(labelWithString: "new surface")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = cfg.color("theme.overlay_text")

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(paletteRow("1", "terminal"))
        stack.addArrangedSubview(paletteRow("2", "editor"))
        stack.addArrangedSubview(paletteRow("3", "agent"))

        center = palette.centerYAnchor.constraint(equalTo: windowGlass.centerYAnchor)
        NSLayoutConstraint.activate([
            center!,
            palette.centerXAnchor.constraint(equalTo: windowGlass.centerXAnchor),
            palette.widthAnchor.constraint(equalToConstant: 200),
        ])
        stack.pin(to: palette, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
    }

    private func paletteRow(_ key: String, _ title: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let k = NSTextField(labelWithString: key)
        k.font = cfg.font(.medium)
        k.textColor = cfg.color("theme.overlay_text")
        k.setContentHuggingPriority(.required, for: .horizontal)

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .medium)
        t.textColor = cfg.color("theme.overlay_subdued")

        row.addArrangedSubview(k)
        row.addArrangedSubview(t)
        return row
    }
}
