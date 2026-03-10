import AppKit
import Foundation
import OsmiumPickerSupport

final class MainController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum SidebarState {
        case hidden
        case tabsPeek
        case picker
    }

    private var tabs: [Surface] = []
    private var selectedTabID: UUID?
    private var saveBinds: [SaveBind] = []
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

    private var pickerMode: SidebarPickerMode?
    private var pickerBaseEntries: [SidebarPickerEntry] = []
    private var pickerEntries: [SidebarPickerEntry] = []
    private var pickerQuery = ""
    private var pickerSelectionIndex = -1
    private var pickerLoadGeneration = 0

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
                setSidebarState(.hidden)
            }
        }
    }

    func handleShortcut(event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if mods == .control && key == "q" || mods == .command && key == "q" {
            NSApp.terminate(nil)
            return true
        }

        if (mods == .option || mods == .command) && key == "p" {
            if paletteVisible {
                dismissPalette()
            }
            togglePicker()
            return true
        }

        if mods == .option && key == "[" {
            cycleTabs(-1)
            return true
        }

        if mods == .option && key == "]" {
            cycleTabs(1)
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

        if sidebarState == .picker {
            return handlePickerKey(event: event, key: key, modifiers: mods)
        }

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
        let index = tabs.firstIndex(where: { $0.tabID == selectedTabID }) ?? 0
        selectedTabID = tabs[(index + delta + tabs.count) % tabs.count].tabID
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
        _ = editor.save(binds: saveBinds)
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
        return FileManager.default.currentDirectoryPath
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
            tableView.reloadData()
        } else if sidebarState == .tabsPeek {
            for row in 0..<tabs.count {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TabCell else { continue }
                let item = tabs[row]
                cell.configure(text: "\(item.kindPrefix) \(item.titleText)", selected: item.tabID == selectedTabID)
            }
        }

        if didChangeSurface, sidebarState == .picker {
            reloadPickerForSelectedSurface()
        }

        syncTableSelection()
        updateTitle()
    }

    private func syncTableSelection() {
        switch sidebarState {
        case .hidden:
            tableView.deselectAll(nil)

        case .tabsPeek:
            guard let id = selectedTabID, let row = tabs.firstIndex(where: { $0.tabID == id }) else {
                tableView.deselectAll(nil)
                return
            }
            guard tableView.selectedRow != row else { return }
            syncingSelection = true
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            syncingSelection = false

        case .picker:
            guard pickerSelectionIndex >= 0, pickerSelectionIndex < pickerEntries.count else {
                tableView.deselectAll(nil)
                return
            }
            guard tableView.selectedRow != pickerSelectionIndex else { return }
            syncingSelection = true
            tableView.selectRowIndexes(IndexSet(integer: pickerSelectionIndex), byExtendingSelection: false)
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
            dismissPicker(focusAfter: false)
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
                openEditor(path: url.path)
            }
            return
        }
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else {
                self?.focusSurface()
                return
            }
            self?.openEditor(path: url.path)
        }
    }

    private func togglePicker() {
        cancelPendingTabsPeek()
        if sidebarState == .picker {
            dismissPicker()
        } else {
            presentPicker()
        }
    }

    private func presentPicker() {
        pickerQuery = ""
        pickerSelectionIndex = -1
        setSidebarState(.picker)
        reloadPickerForSelectedSurface()
        view.window?.makeFirstResponder(tableView)
    }

    private func dismissPicker(focusAfter: Bool = true) {
        guard sidebarState == .picker else { return }
        pickerQuery = ""
        pickerSelectionIndex = -1
        setSidebarState(.hidden)
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
            self.setSidebarState(.tabsPeek)
        }
        pendingTabsPeek = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cfg.tabsSlideDelay, execute: workItem)
    }

    private func cancelPendingTabsPeek() {
        pendingTabsPeek?.cancel()
        pendingTabsPeek = nil
    }

    private func reloadPickerForSelectedSurface() {
        pickerQuery = ""
        pickerSelectionIndex = -1

        if selected() is AgentSurface {
            pickerMode = .recentChats
            pickerBaseEntries = [sidebarInfoEntry("recent chats"), sidebarInfoEntry("loading chats…")]
            applyPickerFilter()
            loadRecentChats()
            return
        }

        let directory = workingDirectory()
        pickerMode = .files(directory: directory)
        loadDirectory(directory)
    }

    private func loadRecentChats() {
        pickerLoadGeneration += 1
        let generation = pickerLoadGeneration
        AgentBridge.loadRecentThreads(cwd: workingDirectory()) { [weak self] threads in
            guard let self, generation == self.pickerLoadGeneration else { return }
            guard self.sidebarState == .picker, self.pickerMode == .recentChats else { return }
            let entries = sidebarRecentChatEntries(threads)
            self.pickerBaseEntries = [sidebarInfoEntry("recent chats")] + (entries.isEmpty ? [sidebarInfoEntry("no recent chats")] : entries)
            self.applyPickerFilter()
        }
    }

    private func loadDirectory(_ directory: String) {
        pickerMode = .files(directory: directory)
        let displayDirectory = directory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        do {
            let entries = try sidebarDirectoryEntries(at: directory)
            pickerBaseEntries = [sidebarInfoEntry(displayDirectory)] + (entries.isEmpty ? [sidebarInfoEntry("empty folder")] : entries)
        } catch {
            pickerBaseEntries = [sidebarInfoEntry(displayDirectory), sidebarInfoEntry("could not read folder")]
        }
        applyPickerFilter()
    }

    private func applyPickerFilter() {
        let filtered = sidebarFilterEntries(pickerBaseEntries, query: pickerQuery)
        if pickerQuery.isEmpty {
            pickerEntries = pickerBaseEntries
        } else if filtered.isEmpty {
            pickerEntries = [sidebarInfoEntry("no matches")]
        } else {
            pickerEntries = filtered
        }

        pickerSelectionIndex = pickerEntries.firstIndex(where: { $0.isActivatable }) ?? -1
        tableView.reloadData()
        syncTableSelection()
    }

    private func handlePickerKey(event: NSEvent, key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch event.keyCode {
        case 53:
            dismissPicker()
            return true
        case 123:
            navigatePickerToParentDirectory()
            return true
        case 124:
            activateSelectedPickerEntry()
            return true
        case 125:
            movePickerSelection(1)
            return true
        case 126:
            movePickerSelection(-1)
            return true
        case 36, 76:
            activateSelectedPickerEntry()
            return true
        case 51, 117:
            backspacePickerQuery()
            return true
        default:
            break
        }

        guard !modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else {
            return false
        }
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
            return false
        }
        guard let scalar = characters.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) else {
            return false
        }

        appendPickerQuery(characters.lowercased())
        return true
    }

    private func handleSidebarTableKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch sidebarState {
        case .picker:
            return handlePickerKey(event: event, key: key, modifiers: modifiers)

        case .tabsPeek:
            switch event.keyCode {
            case 53:
                setSidebarState(.hidden)
                focusSurface()
                return true
            case 125:
                cycleTabs(1)
                return true
            case 126:
                cycleTabs(-1)
                return true
            case 36, 76:
                setSidebarState(.hidden)
                focusSurface()
                return true
            default:
                return false
            }

        case .hidden:
            return false
        }
    }

    private func appendPickerQuery(_ string: String) {
        pickerQuery += string
        applyPickerFilter()
    }

    private func backspacePickerQuery() {
        guard !pickerQuery.isEmpty else { return }
        pickerQuery.removeLast()
        applyPickerFilter()
    }

    private func movePickerSelection(_ delta: Int) {
        let activatableRows = pickerEntries.enumerated().compactMap { offset, entry in
            entry.isActivatable ? offset : nil
        }
        guard !activatableRows.isEmpty else { return }

        let current = activatableRows.firstIndex(of: pickerSelectionIndex) ?? 0
        let next = (current + delta + activatableRows.count) % activatableRows.count
        pickerSelectionIndex = activatableRows[next]
        syncTableSelection()
        tableView.scrollRowToVisible(pickerSelectionIndex)
    }

    private func navigatePickerToParentDirectory() {
        guard case .files(let directory) = pickerMode, directory != "/" else { return }
        pickerQuery = ""
        let parent = URL(fileURLWithPath: directory).deletingLastPathComponent().path.ifEmpty("/")
        loadDirectory(parent)
    }

    private func activateSelectedPickerEntry() {
        guard pickerSelectionIndex >= 0, pickerSelectionIndex < pickerEntries.count else { return }
        activatePickerEntry(pickerEntries[pickerSelectionIndex])
    }

    private func activatePickerEntry(_ entry: SidebarPickerEntry) {
        switch entry.kind {
        case .info:
            return

        case .recentChat:
            activateRecentChat(entry)

        case .parentDirectory, .directory:
            guard let path = entry.path else { return }
            pickerQuery = ""
            loadDirectory(path)

        case .file:
            guard let path = entry.path else { return }
            if shouldOpenInBrowser(path: path) {
                dismissPicker(focusAfter: false)
                openBrowser(path: path)
            } else if sidebarIsLikelyTextFile(at: path) {
                dismissPicker(focusAfter: false)
                openEditor(path: path)
            } else if FileManager.default.isExecutableFile(atPath: path) {
                dismissPicker(focusAfter: false)
                runExecutable(at: path)
            } else {
                dismissPicker(focusAfter: false)
                openWithSystem(at: path)
            }
        }
    }

    private func shouldOpenInBrowser(path: String) -> Bool {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "pdf", "html", "htm":
            return true
        default:
            return false
        }
    }

    private func openBrowser(path: String) {
        install(BrowserSurface(url: URL(fileURLWithPath: path)))
    }

    private func activateRecentChat(_ entry: SidebarPickerEntry) {
        guard let threadId = entry.threadId, let cwd = entry.cwd else { return }
        if let existing = tabs
            .compactMap({ $0 as? AgentSurface })
            .first(where: { $0.currentThreadID == threadId })
        {
            selectedTabID = existing.tabID
            renderTabs()
            dismissPicker(focusAfter: false)
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
                self.dismissPicker(focusAfter: false)
                return
            }

            currentAgent.replaceThread(with: snapshot)
            self.selectedTabID = currentAgent.tabID
            self.renderTabs()
            self.dismissPicker(focusAfter: false)
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

    private func openWithSystem(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path]
        try? process.run()
    }

    @objc private func sidebarRowClicked() {
        guard sidebarState == .picker else { return }
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < pickerEntries.count else { return }
        pickerSelectionIndex = row
        syncTableSelection()
        activateSelectedPickerEntry()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        switch sidebarState {
        case .hidden:
            return 0
        case .tabsPeek:
            return tabs.count
        case .picker:
            return pickerEntries.count
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        34
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch sidebarState {
        case .hidden:
            return nil

        case .tabsPeek:
            let identifier = NSUserInterfaceItemIdentifier("TabCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? TabCell) ?? TabCell(frame: .zero)
            cell.identifier = identifier
            let item = tabs[row]
            cell.configure(text: "\(item.kindPrefix) \(item.titleText)", selected: item.tabID == selectedTabID)
            return cell

        case .picker:
            let identifier = NSUserInterfaceItemIdentifier("SidebarPickerCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarPickerCell) ?? SidebarPickerCell(frame: .zero)
            cell.identifier = identifier
            let entry = pickerEntries[row]
            cell.configure(entry: entry, selected: row == pickerSelectionIndex)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }

        switch sidebarState {
        case .hidden:
            return

        case .tabsPeek:
            guard row < tabs.count else { return }
            selectedTabID = tabs[row].tabID
            renderTabs()

        case .picker:
            guard row < pickerEntries.count else { return }
            pickerSelectionIndex = row
        }
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
        tableView.target = self
        tableView.action = #selector(sidebarRowClicked)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onKeyDown = { [weak self] event in
            self?.handleSidebarTableKey(event) ?? false
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
