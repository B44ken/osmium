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

    func save(binds: [SaveBind]) -> String? { nil }

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

final class TerminalSurface: Surface, @preconcurrency LocalProcessTerminalViewDelegate {
    private let terminalView = LocalProcessTerminalView(frame: .zero)
    private let initialDirectory: String
    private var currentDirectory: String
    private var terminalTitle: String?
    private var started = false

    override var titleText: String {
        let fallback = URL(fileURLWithPath: currentDirectory).lastPathComponent.ifEmpty(currentDirectory)
        return terminalTitle?.ifEmpty(fallback) ?? fallback
    }
    override var preferredFirstResponder: NSResponder? { terminalView }
    var cwd: String { currentDirectory }

    init(cwd: String) {
        initialDirectory = cwd
        currentDirectory = cwd
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
        }
        window?.makeFirstResponder(terminalView)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        terminalTitle = trimmed.isEmpty ? nil : trimmed
        onStateChange?()
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

    override func save(binds: [SaveBind]) -> String? {
        let url = URL(fileURLWithPath: filePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try editorController.text.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            onStateChange?()
            let matching = binds.filter { $0.event == "save:\(filePath)" || $0.event == "save:\(url.lastPathComponent)" }
            for bind in matching {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-lc", bind.command]
                p.currentDirectoryURL = url.deletingLastPathComponent()
                try? p.run()
            }
            if let last = matching.last { return "saved \(url.lastPathComponent) and ran `\(last.command)`" }
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
                wrapLines: false,
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
        webView.load(URLRequest(url: currentURL))
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
}
