import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftTerm
import WebKit

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

    func save() -> String? { nil }

    func activate(in window: NSWindow?) {
        guard let r = preferredFirstResponder else { return }
        window?.makeFirstResponder(r)
    }

    func makeRoot() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        view = root
        return root
    }
}

final class TrackingTerminalView: LocalProcessTerminalView {
    var onHostOutput: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onHostOutput?()
    }
}

final class TerminalSurface: Surface, @preconcurrency LocalProcessTerminalViewDelegate {
    private let terminalView = TrackingTerminalView(frame: .zero)
    private let initialDirectory: String
    private var currentDirectory: String
    private var started = false
    private var pendingCommands: [String] = []
    private var refreshWorkItem: DispatchWorkItem?

    override var titleText: String {
        URL(fileURLWithPath: currentDirectory).lastPathComponent.ifEmpty(currentDirectory)
    }
    override var preferredFirstResponder: NSResponder? { terminalView }
    var cwd: String { currentDirectory }
    func resolvedWorkingDirectory() -> String { refreshWorkingDirectoryFromProcess() ?? currentDirectory }

    init(cwd: String, initialCommand: String? = nil) {
        initialDirectory = cwd
        currentDirectory = cwd
        if let initialCommand {
            pendingCommands = [initialCommand]
        }
        super.init(kindPrefix: "T")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = makeRoot()
        terminalView.processDelegate = self
        terminalView.onHostOutput = { [weak self] in
            self?.scheduleProcessStateRefresh()
        }
        terminalView.optionAsMetaKey = true
        terminalView.nativeForegroundColor = cfg.color("theme.terminal_foreground")
        terminalView.nativeBackgroundColor = cfg.color("theme.terminal_bg")
        terminalView.caretColor = cfg.color("theme.terminal_cursor")
        terminalView.font = cfg.font
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
        root.layer?.backgroundColor = cfg.color("theme.terminal_bg").cgColor
        root.addSubview(terminalView)
        terminalView.pin(to: root, insets: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
    }

    override func activate(in window: NSWindow?) {
        if !started {
            started = true
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            terminalView.startProcess(
                executable: shell,
                args: ["-l"],
                execName: "-\(URL(fileURLWithPath: shell).lastPathComponent)",
                currentDirectory: initialDirectory
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.flushPendingCommands()
            }
        } else {
            flushPendingCommands()
        }
        window?.makeFirstResponder(terminalView)
    }

    func run(command: String) {
        pendingCommands.append(command)
        if started {
            flushPendingCommands()
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title _: String) {
        scheduleProcessStateRefresh()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        currentDirectory = directory
        onStateChange?()
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let msg = exitCode.map { $0 == 0 ? "terminal exited" : "terminal exited (\($0))" } ?? "terminal exited"
        DispatchQueue.main.async { [weak self] in
            self?.onRequestClose?(msg)
        }
    }

    private func flushPendingCommands() {
        guard started, !pendingCommands.isEmpty else { return }
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands {
            terminalView.send(txt: command)
            terminalView.send(txt: "\n")
        }
        scheduleProcessStateRefresh()
    }

    private func scheduleProcessStateRefresh() {
        guard started else { return }
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            _ = self?.refreshWorkingDirectoryFromProcess()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    @discardableResult
    private func refreshWorkingDirectoryFromProcess() -> String? {
        guard started else { return currentDirectory }
        let pid = terminalView.process.shellPid
        guard pid > 0 else { return currentDirectory }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-d", "cwd", "-p", String(pid), "-Fn"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let directory = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.first == "n" else { return nil }
                let value = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            .first

        guard let directory else { return nil }
        if currentDirectory != directory {
            currentDirectory = directory
            onStateChange?()
        }
        return directory
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
        let lang = CodeLanguage.detectLanguageFrom(
            url: url,
            prefixBuffer: String(source.prefix(4096)),
            suffixBuffer: String(source.suffix(2048))
        )
        editorController = TextViewController(
            string: source,
            language: lang,
            configuration: Self.editorConfig(),
            cursorPositions: [],
            highlightProviders: [TreeSitterClient()],
            undoManager: CEUndoManager()
        )
        super.init(kindPrefix: "E")
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func loadView() {
        let root = makeRoot()
        addChild(editorController)
        root.addSubview(editorController.view)
        editorController.view.pin(to: root)
        editorController.textView.wrapLines = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: TextView.textDidChangeNotification,
            object: editorController.textView
        )
    }

    override func activate(in window: NSWindow?) {
        window?.makeFirstResponder(editorController.textView)
    }

    override func save() -> String? {
        let url = URL(fileURLWithPath: filePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try editorController.text.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            onStateChange?()
            return "saved \(url.lastPathComponent)"
        } catch {
            return "save failed: \(error.localizedDescription)"
        }
    }

    func matches(path: String) -> Bool { currentPath == path }

    @objc private func textDidChange() {
        dirty = true
        onStateChange?()
    }

    private static func editorConfig() -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: cfg.editorTheme,
                useThemeBackground: true,
                font: cfg.font(.regular),
                lineHeightMultiple: 1.15,
                letterSpacing: 1.0,
                wrapLines: true,
                useSystemCursor: true,
                tabWidth: 4,
                bracketPairEmphasis: .flash
            ),
            behavior: .init(
                isEditable: true,
                isSelectable: true,
                indentOption: .spaces(count: 4),
                reformatAtColumn: 100
            ),
            layout: .init(
                editorOverscroll: 0.08,
                contentInsets: NSEdgeInsets(top: 12, left: 0, bottom: 20, right: 0),
                additionalTextInsets: NSEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
            ),
            peripherals: .init(
                showGutter: true,
                showMinimap: false,
                showReformattingGuide: false,
                showFoldingRibbon: false,
                invisibleCharactersConfiguration: .empty,
                warningCharacters: []
            )
        )
    }
}

final class BrowserSurface: Surface, WKNavigationDelegate {
    private let webView = WKWebView(frame: .zero)
    private var currentURL: URL

    override var titleText: String { currentURL.host ?? currentURL.absoluteString }
    override var preferredFirstResponder: NSResponder? { webView }

    init(url: URL) {
        currentURL = url
        super.init(kindPrefix: "W")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = makeRoot()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        root.addSubview(webView)
        webView.pin(to: root)
        loadCurrentURL()
    }

    override func activate(in window: NSWindow?) {
        window?.makeFirstResponder(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            currentURL = url
            onStateChange?()
        }
    }

    private func loadCurrentURL() {
        if currentURL.isFileURL {
            let accessURL = currentURL.hasDirectoryPath
                ? currentURL
                : currentURL.deletingLastPathComponent()
            webView.loadFileURL(currentURL, allowingReadAccessTo: accessURL)
            return
        }
        webView.load(URLRequest(url: currentURL))
    }
}
