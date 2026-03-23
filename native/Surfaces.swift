import AppKit
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

    func save() -> Bool { false }

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
        terminalView.font = cfg.terminalFont
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
        root.layer?.backgroundColor = cfg.color("theme.terminal_bg").cgColor
        root.addSubview(terminalView)
        terminalView.pin(to: root, insets: NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
    }

    override func activate(in window: NSWindow?) {
        startIfNeeded()
        flushPendingCommands()
        window?.makeFirstResponder(terminalView)
    }

    func run(command: String) {
        pendingCommands.append(command)
        startIfNeeded()
        flushPendingCommands()
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

    private func startIfNeeded() {
        _ = view
        guard !started else { return }
        started = true
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            execName: "-\(URL(fileURLWithPath: shell).lastPathComponent)",
            currentDirectory: initialDirectory
        )
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

final class EditorSurface: Surface, WKScriptMessageHandler, WKNavigationDelegate {
    private let filePath: String
    private let webView: WKWebView
    private var currentText: String
    private var dirty = false
    private var ready = false
    private(set) var hotCommand: String?
    private var hotTerminalID: UUID?

    override var titleText: String {
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        return dirty ? "\(name) *" : name
    }
    override var preferredFirstResponder: NSResponder? { webView }
    var currentPath: String { filePath }

    init(path: String, hotCommand: String? = nil) {
        filePath = path
        self.hotCommand = hotCommand
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        currentText = source
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(kindPrefix: "E")
        controller.add(self, name: "editorState")
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editorState")
    }

    override func loadView() {
        let root = makeRoot()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        root.addSubview(webView)
        webView.pin(to: root)
        webView.loadHTMLString(
            Self.editorHTML(path: filePath, text: currentText),
            baseURL: URL(string: "https://osmium.local")
        )
    }

    override func activate(in window: NSWindow?) {
        window?.makeFirstResponder(webView)
        if ready {
            webView.evaluateJavaScript("window.osmiumEditor?.focus()", completionHandler: nil)
        }
    }

    override func save() -> Bool {
        let url = URL(fileURLWithPath: filePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try currentText.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            if ready {
                webView.evaluateJavaScript("window.osmiumEditor?.markSaved()", completionHandler: nil)
            }
            onStateChange?()
            return true
        } catch {
            return false
        }
    }

    func matches(path: String) -> Bool { currentPath == path }
    func updateHotCommand(_ command: String?) { hotCommand = command }
    func hotTerminal(in tabs: [Surface]) -> TerminalSurface? {
        guard let hotTerminalID else { return nil }
        return tabs.first(where: { $0.tabID == hotTerminalID }) as? TerminalSurface
    }
    func bindHotTerminal(_ terminal: TerminalSurface) { hotTerminalID = terminal.tabID }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        webView.evaluateJavaScript("window.osmiumEditor?.focus()", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "editorState" else { return }
        guard let body = message.body as? [String: Any] else { return }
        if let text = body["text"] as? String {
            currentText = text
        }
        if let nextDirty = body["dirty"] as? Bool, nextDirty != dirty {
            dirty = nextDirty
            onStateChange?()
        }
    }

    private static func editorHTML(path: String, text: String) -> String {
        let payload = jsonString([
            "path": path,
            "text": text,
            "fontFamily": cfg.monoFontName,
            "fontSize": Int(cfg.editorFontSize),
            "theme": [
                "background": cfg.string("theme.editor_bg"),
                "foreground": cfg.string("theme.editor_text"),
                "selection": cfg.string("theme.editor_selection"),
                "lineHighlight": cfg.string("theme.editor_line_highlight"),
                "cursor": cfg.string("theme.editor_cursor"),
                "invisibles": cfg.string("theme.editor_invisibles"),
                "keywords": cfg.string("theme.editor_keywords"),
                "commands": cfg.string("theme.editor_commands"),
                "types": cfg.string("theme.editor_types"),
                "attributes": cfg.string("theme.editor_attributes"),
                "variables": cfg.string("theme.editor_variables"),
                "values": cfg.string("theme.editor_values"),
                "numbers": cfg.string("theme.editor_numbers"),
                "strings": cfg.string("theme.editor_strings"),
                "characters": cfg.string("theme.editor_characters"),
                "comments": cfg.string("theme.editor_comments"),
            ],
        ])

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body, #editor {
              margin: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: \(cfg.string("theme.editor_bg"));
            }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs/loader.js"></script>
        </head>
        <body>
          <div id="editor"></div>
          <script>
            const boot = \(payload)
            const solid = (hex, fallback = '#ffffff') => {
              const cleaned = String(hex || '').replace(/[^0-9a-f]/ig, '')
              return cleaned.length >= 6 ? `#${cleaned.slice(0, 6)}` : fallback
            }
            const token = (hex, fallback = 'ffffff') => solid(hex, `#${fallback}`).slice(1)
            const ext = (boot.path.split('.').pop() || '').toLowerCase()
            const languageByExt = {
              js: 'javascript',
              mjs: 'javascript',
              cjs: 'javascript',
              ts: 'typescript',
              tsx: 'typescript',
              jsx: 'javascript',
              json: 'json',
              md: 'markdown',
              py: 'python',
              rb: 'ruby',
              go: 'go',
              rs: 'rust',
              swift: 'swift',
              sh: 'shell',
              zsh: 'shell',
              bash: 'shell',
              html: 'html',
              css: 'css',
              scss: 'scss',
              yml: 'yaml',
              yaml: 'yaml',
              toml: 'ini',
              txt: 'plaintext'
            }
            const language = languageByExt[ext] || 'plaintext'
            require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs' } })
            require(['vs/editor/editor.main'], () => {
              monaco.editor.defineTheme('osmium', {
                base: 'vs-dark',
                inherit: true,
                rules: [
                  { token: 'comment', foreground: token(boot.theme.comments) },
                  { token: 'keyword', foreground: token(boot.theme.keywords), fontStyle: 'bold' },
                  { token: 'keyword.control', foreground: token(boot.theme.keywords), fontStyle: 'bold' },
                  { token: 'keyword.operator', foreground: token(boot.theme.commands) },
                  { token: 'function', foreground: token(boot.theme.commands) },
                  { token: 'function.call', foreground: token(boot.theme.commands) },
                  { token: 'support.function', foreground: token(boot.theme.commands) },
                  { token: 'type', foreground: token(boot.theme.types) },
                  { token: 'type.identifier', foreground: token(boot.theme.types) },
                  { token: 'support.type', foreground: token(boot.theme.types) },
                  { token: 'attribute.name', foreground: token(boot.theme.attributes) },
                  { token: 'tag.attribute.name', foreground: token(boot.theme.attributes) },
                  { token: 'variable', foreground: token(boot.theme.variables) },
                  { token: 'identifier', foreground: token(boot.theme.variables) },
                  { token: 'parameter', foreground: token(boot.theme.variables) },
                  { token: 'constant', foreground: token(boot.theme.values) },
                  { token: 'constant.language', foreground: token(boot.theme.values) },
                  { token: 'constant.other', foreground: token(boot.theme.values) },
                  { token: 'number', foreground: token(boot.theme.numbers) },
                  { token: 'string', foreground: token(boot.theme.strings) },
                  { token: 'regexp', foreground: token(boot.theme.strings) },
                  { token: 'constant.character', foreground: token(boot.theme.characters) },
                  { token: 'string.escape', foreground: token(boot.theme.characters) }
                ],
                colors: {
                  'editor.background': solid(boot.theme.background, '#101419'),
                  'editor.foreground': solid(boot.theme.foreground, '#e7ebf2'),
                  'editor.selectionBackground': solid(boot.theme.selection, '#25415c'),
                  'editor.lineHighlightBackground': solid(boot.theme.lineHighlight, '#171d24'),
                  'editorCursor.foreground': solid(boot.theme.cursor, '#e7ebf2'),
                  'editorWhitespace.foreground': solid(boot.theme.invisibles, '#556170'),
                  'editorIndentGuide.background1': solid(boot.theme.invisibles, '#556170'),
                  'editorIndentGuide.activeBackground1': solid(boot.theme.types, '#70c7ff'),
                  'editorLineNumber.foreground': solid(boot.theme.invisibles, '#556170'),
                  'editorLineNumber.activeForeground': solid(boot.theme.foreground, '#e7ebf2'),
                  'editorGutter.background': solid(boot.theme.background, '#101419')
                }
              })
              const editor = monaco.editor.create(document.getElementById('editor'), {
                value: boot.text,
                language,
                theme: 'osmium',
                automaticLayout: true,
                minimap: { enabled: false },
                scrollBeyondLastLine: false,
                wordWrap: 'off',
                fontFamily: boot.fontFamily,
                fontSize: boot.fontSize,
                lineHeight: Math.round(boot.fontSize * 1.45),
                letterSpacing: 0.2,
                fontLigatures: false,
                tabSize: 2,
                insertSpaces: true,
                padding: { top: 8, bottom: 24 },
                glyphMargin: false,
                folding: true,
                showFoldingControls: 'never',
                foldingHighlight: false,
                lineNumbersMinChars: 3,
                overviewRulerLanes: 0,
                hideCursorInOverviewRuler: true,
                renderValidationDecorations: 'off',
                renderLineHighlightOnlyWhenFocus: true,
                cursorBlinking: 'solid',
                smoothScrolling: false,
                scrollbar: {
                  verticalScrollbarSize: 8,
                  horizontalScrollbarSize: 8,
                  useShadows: false,
                  alwaysConsumeMouseWheel: false
                },
                stickyScroll: { enabled: false },
                occurrencesHighlight: 'off',
                selectionHighlight: false,
                roundedSelection: false
              })
              let lastSaved = boot.text
              let pending = null
              const postState = () => {
                const text = editor.getValue()
                window.webkit.messageHandlers.editorState.postMessage({
                  text,
                  dirty: text !== lastSaved
                })
              }
              editor.onDidChangeModelContent(() => {
                clearTimeout(pending)
                pending = setTimeout(postState, 80)
              })
              window.osmiumEditor = {
                focus: () => editor.focus(),
                markSaved: () => {
                  lastSaved = editor.getValue()
                  postState()
                }
              }
              postState()
              editor.focus()
            })
          </script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value)
        return String(data: data, encoding: .utf8)!
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
