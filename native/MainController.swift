import AppKit
import Foundation

final class MainController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum SidebarState {
        case hidden
        case tabsPeek
        case picker
    }

    private enum RecentThreadsStatus: String {
        case idle
        case loading
        case loaded
    }

    private var tabs: [Surface] = []
    private var selectedTabID: UUID?
    private var sidebarState: SidebarState = .hidden
    private var paletteVisible = false
    private var displayedSurfaceID: UUID?
    private var currentPanel: GlassPanel?

    private let ci: CGFloat = 8

    private let windowGlass = NSVisualEffectView()
    private let contentContainer = NSView()
    private let sidebar = NSVisualEffectView()
    private let tableView = SidebarTableView()
    private let sidebarScroll = NSScrollView()
    private let palette = NSVisualEffectView()
    private var sidebarLeading: NSLayoutConstraint?
    private var sidebarWidth: NSLayoutConstraint?
    private var center: NSLayoutConstraint?

    private var syncingSelection = false
    private var pendingTabsPeek: DispatchWorkItem?

    private var recentThreads: [AgentThreadSummary] = []
    private var recentThreadsStatus: RecentThreadsStatus = .idle
    private var recentThreadsLoadGeneration = 0
    private var sidebarRows: [SidebarBridgeRow] = []
    private var sidebarSelectionIndex = -1
    private var sidebarBridgeState: SidebarBridgeState?

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
            install(TerminalSurface(cwd: cmd.cwd ?? cfg.startDirectory))
        case "open-agent":
            openAgent(cwd: cmd.cwd ?? workingDirectory())
        case "open-editor":
            guard let path = cmd.path else { return }
            openEditor(path: path, hotCommand: cmd.hot)
        case "open-browser":
            guard let raw = cmd.url, let url = URL(string: raw) else { return }
            install(BrowserSurface(url: url))
        default:
            break
        }
    }

    func handleModifierFlags(_ flags: NSEvent.ModifierFlags) {
        let optionOnly = flags.intersection([.shift, .control, .option, .command]) == .option
        guard sidebarState != .picker else {
            if !optionOnly {
                cancelPendingTabsPeek()
            }
            return
        }

        if optionOnly {
            scheduleTabsPeek()
        } else {
            cancelPendingTabsPeek()
            if sidebarState == .tabsPeek {
                _ = reduceSidebar(action: SidebarBridgeAction(type: "hideTabsPeek", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))
            }
        }
    }

    func handleShortcut(event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if mods == .option && shouldCancelTabsPeek(for: event) {
            cancelPendingTabsPeek()
            if sidebarState == .tabsPeek {
                _ = reduceSidebar(action: SidebarBridgeAction(type: "hideTabsPeek", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))
            }
            return false
        }

        if mods == .control && key == "q" || mods == .command && key == "q" {
            NSApp.terminate(nil)
            return true
        }

        if mods == .option && key == "p" {
            if paletteVisible {
                dismissPalette()
            }
            togglePicker()
            return true
        }

        if mods == .option && key == "[" {
            _ = reduceSidebar(action: SidebarBridgeAction(type: "cycleTabs", delta: -1, keyCode: nil, key: nil, modifiers: nil, row: nil))
            return true
        }

        if mods == .option && key == "]" {
            _ = reduceSidebar(action: SidebarBridgeAction(type: "cycleTabs", delta: 1, keyCode: nil, key: nil, modifiers: nil, row: nil))
            return true
        }

        if paletteVisible {
            return handlePaletteKey(key)
        }

        if mods == .command && key == "t" {
            presentPalette()
            return true
        }

        if mods == .command && key == "w" {
            closeSelectedTab()
            return true
        }

        if mods == .command && key == "s" {
            saveEditor()
            return true
        }

        if sidebarState != .hidden {
            return handleSidebarKey(event: event, key: key, modifiers: mods)
        }

        return false
    }

    private func openEditor(path: String, hotCommand: String?) {
        if let existing = tabs.compactMap({ $0 as? EditorSurface }).first(where: { $0.matches(path: path) }) {
            if hotCommand != nil {
                existing.updateHotCommand(hotCommand)
            }
            selectedTabID = existing.tabID
            renderTabs()
            return
        }
        install(EditorSurface(path: path, hotCommand: hotCommand))
    }

    private func openAgent(cwd: String) {
        if let existing = tabs.compactMap({ $0 as? AgentSurface }).first(where: { $0.cwd == cwd }) {
            selectedTabID = existing.tabID
            renderTabs()
            return
        }
        install(AgentSurface(cwd: cwd))
    }

    private func install(_ surface: Surface, select: Bool = true) {
        addChild(surface)
        surface.onStateChange = { [weak self] in self?.renderTabs() }
        surface.onRequestClose = { [weak self, weak surface] _ in
            guard let self, let surface else { return }
            self.closeTab(surface.tabID)
        }
        tabs.append(surface)
        if select {
            selectedTabID = surface.tabID
        }
        renderTabs()
    }

    private func closeSelectedTab() {
        guard let id = selectedTabID else { return }
        closeTab(id)
    }

    private func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.tabID == id }) else { return }
        let surface = tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].tabID : tabs.last?.tabID
        }
        surface.removeFromParent()
        renderTabs()
    }

    private func saveEditor() {
        guard let editor = selected() as? EditorSurface else { return }
        if editor.save() {
            runHotCommand(for: editor)
        }
        renderTabs()
    }

    private func selected() -> Surface? {
        tabs.first { $0.tabID == selectedTabID }
    }

    private func workingDirectory() -> String {
        if let terminal = selected() as? TerminalSurface { return terminal.resolvedWorkingDirectory() }
        if let editor = selected() as? EditorSurface {
            return URL(fileURLWithPath: editor.currentPath).deletingLastPathComponent().path
        }
        if let agent = selected() as? AgentSurface { return agent.cwd }
        return cfg.startDirectory
    }

    private func renderTabs() {
        let surface = selected()
        let didChangeSurface = surface?.tabID != displayedSurfaceID

        if didChangeSurface {
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
        }

        if sidebarState != .hidden {
            _ = reduceSidebar(action: SidebarBridgeAction(type: didChangeSurface ? "surfaceChanged" : "refresh", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))
        }

        syncTableSelection()
        updateTitle()
    }

    private func syncTableSelection() {
        switch sidebarState {
        case .hidden:
            tableView.deselectAll(nil)

        case .tabsPeek, .picker:
            guard sidebarSelectionIndex >= 0, sidebarSelectionIndex < sidebarRows.count else {
                tableView.deselectAll(nil)
                return
            }
            guard tableView.selectedRow != sidebarSelectionIndex else { return }
            syncingSelection = true
            tableView.selectRowIndexes(IndexSet(integer: sidebarSelectionIndex), byExtendingSelection: false)
            syncingSelection = false
        }
    }

    private func updateTitle() {
        view.window?.title = selected().map { "osmium   \($0.kindPrefix) \($0.titleText)" } ?? "osmium"
    }

    func focusSurface(attempt: Int = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.view.window, let surface = self.selected() else { return }
            surface.activate(in: window)
            if let responder = surface.preferredFirstResponder, !(window.firstResponder === responder), attempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.focusSurface(attempt: attempt + 1)
                }
            }
        }
    }

    private func setSidebarState(_ state: SidebarState, animated: Bool = true) {
        guard sidebarState != state else {
            updateSidebarChrome()
            return
        }

        sidebarState = state
        updateSidebarChrome()

        let targetWidth = state == .picker ? cfg.pickerSidebarWidth : cfg.tabsSidebarWidth
        sidebarLeading?.constant = state == .hidden ? -cfg.pickerSidebarWidth - ci : ci
        sidebarWidth?.constant = targetWidth

        if animated {
            animate(cfg.tabsSlideDuration) {
                self.view.layoutSubtreeIfNeeded()
            }
        } else {
            view.layoutSubtreeIfNeeded()
        }
    }

    private func updateSidebarChrome() {
        tableView.reloadData()
        syncTableSelection()
    }

    private func configureSidebarCell(_ cell: SidebarRowCell, row: Int) {
        guard row >= 0, row < sidebarRows.count else { return }
        let item = sidebarRows[row]
        if item.kind == "tab" {
            cell.configureTab(text: item.primaryText, selected: row == sidebarSelectionIndex)
        } else {
            cell.configure(
                primaryText: item.primaryText,
                secondaryText: item.secondaryText,
                isInfo: item.kind == "info",
                selected: row == sidebarSelectionIndex
            )
        }
    }

    @discardableResult
    private func reduceSidebar(action: SidebarBridgeAction, focusTable: Bool = false) -> Bool {
        guard let response = AppLogicBridge.shared.reduceSidebar(
            state: sidebarBridgeState,
            context: sidebarContext(),
            action: action
        ) else {
            return false
        }

        applySidebarResponse(response, focusTable: focusTable)
        return true
    }

    private func applySidebarResponse(_ response: SidebarBridgeResult, focusTable: Bool) {
        sidebarBridgeState = response.state
        sidebarRows = response.rows
        sidebarSelectionIndex = response.selectionIndex

        let nextState = sidebarState(for: response.state.mode)
        setSidebarState(nextState)

        if focusTable, nextState != .hidden {
            view.window?.makeFirstResponder(tableView)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.view.window?.makeFirstResponder(self.tableView)
            }
        }

        if nextState == .picker, selected() is AgentSurface, recentThreadsStatus == .idle {
            loadRecentThreads()
        }

        if let intent = response.intent {
            handleSidebarIntent(intent)
        }
    }

    private func sidebarState(for mode: String) -> SidebarState {
        switch mode {
        case "tabsPeek":
            return .tabsPeek
        case "picker":
            return .picker
        default:
            return .hidden
        }
    }

    private func sidebarContext() -> SidebarBridgeContext {
        let tabContexts = tabs.map { surface in
            SidebarBridgeTabContext(
                id: surface.tabID.uuidString,
                kind: surfaceKind(surface),
                kindPrefix: surface.kindPrefix,
                title: surface.titleText,
                currentThreadId: (surface as? AgentSurface)?.currentThreadID
            )
        }
        let currentSurface = selected().map {
            SidebarBridgeSurfaceContext(
                kind: surfaceKind($0),
                cwd: surfaceWorkingDirectory($0),
                threadId: ($0 as? AgentSurface)?.currentThreadID
            )
        } ?? SidebarBridgeSurfaceContext(kind: "unknown", cwd: cfg.startDirectory, threadId: nil)
        let recent = recentThreads.map {
            SidebarBridgeRecentThreadContext(
                threadId: $0.threadId,
                cwd: $0.cwd,
                title: $0.title,
                preview: $0.preview,
                updatedAt: $0.updatedAt
            )
        }
        return SidebarBridgeContext(
            tabs: tabContexts,
            selectedTabId: selectedTabID?.uuidString,
            currentSurface: currentSurface,
            recentThreadsStatus: recentThreadsStatus.rawValue,
            recentThreads: recent
        )
    }

    private func surfaceKind(_ surface: Surface) -> String {
        switch surface {
        case is AgentSurface:
            return "agent"
        case is TerminalSurface:
            return "terminal"
        case is EditorSurface:
            return "editor"
        case is BrowserSurface:
            return "browser"
        default:
            return "unknown"
        }
    }

    private func surfaceWorkingDirectory(_ surface: Surface) -> String {
        if let terminal = surface as? TerminalSurface { return terminal.resolvedWorkingDirectory() }
        if let editor = surface as? EditorSurface {
            return URL(fileURLWithPath: editor.currentPath).deletingLastPathComponent().path
        }
        if let agent = surface as? AgentSurface { return agent.cwd }
        return cfg.startDirectory
    }

    private func handleSidebarKey(event: NSEvent, key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let action = SidebarBridgeAction(
            type: "sidebarKey",
            delta: nil,
            keyCode: Int(event.keyCode),
            key: key,
            modifiers: sidebarModifiers(modifiers),
            row: nil
        )
        return reduceSidebar(action: action)
    }

    private func sidebarModifiers(_ modifiers: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if modifiers.contains(.shift) { result.append("shift") }
        if modifiers.contains(.control) { result.append("control") }
        if modifiers.contains(.option) { result.append("option") }
        if modifiers.contains(.command) { result.append("command") }
        return result
    }

    private func handleSidebarIntent(_ intent: SidebarBridgeIntent) {
        switch intent.type {
        case "selectTab":
            guard let tabId = intent.tabId, let uuid = UUID(uuidString: tabId) else { return }
            selectedTabID = uuid
            renderTabs()
        case "replaceAgentThread":
            guard let threadId = intent.threadId, let cwd = intent.cwd else { return }
            replaceCurrentAgentThread(threadId: threadId, cwd: cwd)
        case "openBrowser":
            guard let path = intent.path else { return }
            openBrowser(path: path)
        case "openEditor":
            guard let path = intent.path else { return }
            openEditor(path: path, hotCommand: nil)
        case "runExecutable":
            guard let path = intent.path else { return }
            runExecutable(at: path)
        case "openSystem":
            guard let path = intent.path else { return }
            openWithSystem(at: path)
        default:
            break
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
        if sidebarState == .picker {
            hideSidebar(focusAfter: false)
        }

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
                openEditor(path: url.path, hotCommand: nil)
            }
            return
        }
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else {
                self?.focusSurface()
                return
            }
            self?.openEditor(path: url.path, hotCommand: nil)
        }
    }

    private func togglePicker() {
        cancelPendingTabsPeek()
        if reduceSidebar(action: SidebarBridgeAction(type: "togglePicker", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil), focusTable: true),
           sidebarState == .picker,
           selected() is AgentSurface,
           recentThreadsStatus == .idle
        {
            loadRecentThreads()
        }
    }

    private func hideSidebar(focusAfter: Bool = true) {
        guard sidebarState != .hidden else { return }
        _ = reduceSidebar(action: SidebarBridgeAction(type: "dismiss", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))
        if focusAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) { [weak self] in
                self?.focusSurface()
            }
        }
    }

    private func scheduleTabsPeek() {
        guard sidebarState != .tabsPeek else { return }
        if pendingTabsPeek != nil { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingTabsPeek = nil
            guard self.sidebarState != .picker else { return }
            _ = self.reduceSidebar(action: SidebarBridgeAction(type: "showTabsPeek", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))
        }
        pendingTabsPeek = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cfg.tabsSlideDelay, execute: workItem)
    }

    private func cancelPendingTabsPeek() {
        pendingTabsPeek?.cancel()
        pendingTabsPeek = nil
    }

    private func shouldCancelTabsPeek(for event: NSEvent) -> Bool {
        guard pendingTabsPeek != nil || sidebarState == .tabsPeek else { return false }
        switch event.keyCode {
        case 51, 117, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    private func loadRecentThreads() {
        recentThreadsStatus = .loading
        _ = reduceSidebar(action: SidebarBridgeAction(type: "refresh", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))

        recentThreadsLoadGeneration += 1
        let generation = recentThreadsLoadGeneration
        AgentBridge.loadRecentThreads(cwd: workingDirectory()) { [weak self] threads in
            guard let self, generation == self.recentThreadsLoadGeneration else { return }
            self.recentThreads = threads
            self.recentThreadsStatus = .loaded
            _ = self.reduceSidebar(action: SidebarBridgeAction(type: "refresh", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: nil))
        }
    }

    private func openBrowser(path: String) {
        install(BrowserSurface(url: URL(fileURLWithPath: path)))
    }

    private func replaceCurrentAgentThread(threadId: String, cwd: String) {
        if let existing = tabs
            .compactMap({ $0 as? AgentSurface })
            .first(where: { $0.currentThreadID == threadId })
        {
            selectedTabID = existing.tabID
            renderTabs()
            hideSidebar(focusAfter: false)
            return
        }

        guard let currentAgent = selected() as? AgentSurface else { return }
        AgentBridge.loadThreadSnapshot(cwd: cwd, threadId: threadId) { [weak self, weak currentAgent] snapshot in
            guard let self, let currentAgent, let snapshot else { return }
            if let existing = self.tabs
                .compactMap({ $0 as? AgentSurface })
                .first(where: { $0 !== currentAgent && $0.currentThreadID == snapshot.threadId })
            {
                self.selectedTabID = existing.tabID
                self.renderTabs()
                self.hideSidebar(focusAfter: false)
                return
            }

            currentAgent.replaceThread(with: snapshot)
            self.selectedTabID = currentAgent.tabID
            self.renderTabs()
            self.hideSidebar(focusAfter: false)
        }
    }

    private func runExecutable(at path: String) {
        let command = shellQuote(path)
        if let terminal = selected() as? TerminalSurface {
            terminal.run(command: command)
            terminal.activate(in: view.window)
            return
        }

        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        install(TerminalSurface(cwd: directory, initialCommand: command))
    }

    private func runHotCommand(for editor: EditorSurface) {
        guard let command = editor.hotCommand else { return }
        if let terminal = editor.hotTerminal(in: tabs) {
            terminal.run(command: command)
            return
        }

        let directory = URL(fileURLWithPath: editor.currentPath).deletingLastPathComponent().path
        let terminal = TerminalSurface(cwd: directory, initialCommand: command)
        editor.bindHotTerminal(terminal)
        install(terminal, select: false)
    }

    private func openWithSystem(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path]
        try? process.run()
    }

    @objc private func sidebarRowClicked() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < sidebarRows.count else { return }
        _ = reduceSidebar(
            action: SidebarBridgeAction(type: "clickRow", delta: nil, keyCode: nil, key: nil, modifiers: nil, row: row)
        )
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        sidebarState == .hidden ? 0 : sidebarRows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        34
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch sidebarState {
        case .hidden:
            return nil
        case .tabsPeek, .picker:
            let identifier = NSUserInterfaceItemIdentifier("SidebarRowCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarRowCell) ?? SidebarRowCell(frame: .zero)
            cell.identifier = identifier
            configureSidebarCell(cell, row: row)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection else { return }
        tableView.reloadData()
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
        tableView.intercellSpacing = NSSize(width: 0, height: 2.4)
        tableView.rowHeight = 34
        tableView.target = self
        tableView.action = #selector(sidebarRowClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onKeyDown = { [weak self] event in
            guard let self else { return false }
            let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            return self.handleSidebarKey(event: event, key: key, modifiers: modifiers)
        }

        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarScroll.borderType = .noBorder
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.scrollerStyle = .overlay
        sidebarScroll.documentView = tableView
        sidebar.addSubview(sidebarScroll)

        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: windowGlass.leadingAnchor, constant: -cfg.pickerSidebarWidth - ci)
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: cfg.tabsSidebarWidth)

        sidebarLeading?.isActive = true
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

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = cfg.font(.medium)
        keyLabel.textColor = cfg.color("theme.overlay_text")
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = cfg.color("theme.overlay_subdued")

        row.addArrangedSubview(keyLabel)
        row.addArrangedSubview(titleLabel)
        return row
    }
}
