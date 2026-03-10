import AppKit
import Darwin
import Foundation

final class GlassPanel: NSVisualEffectView {
    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let v = contentView else { return }
            addSubview(v)
            v.pin(to: self)
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
        super.init(frame: frame)
        wantsLayer = true
        highlight.glass(.selection, radius: 10)
        highlight.alphaValue = 0
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

final class CommandServer: @unchecked Sendable {
    private let socketURL: URL
    private let handler: @MainActor @Sendable (AppCommand) -> Void
    private var fd: Int32 = -1
    private var running = false

    init(socketURL: URL, handler: @escaping @MainActor @Sendable (AppCommand) -> Void) {
        self.socketURL = socketURL
        self.handler = handler
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
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, len)
            }
        }
        guard result == 0 else {
            let e = errno
            close(fd)
            fd = -1
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(e))
        }
        guard listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            fd = -1
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(e))
        }
        running = true
        Thread { [weak self] in
            self?.acceptLoop()
        }.start()
    }

    func stop() {
        running = false
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptLoop() {
        while running {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                usleep(40_000)
                continue
            }
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(client, &buf, buf.count)
                if n > 0 { data.append(buf, count: n) }
                else { break }
            }
            close(client)
            guard let payload = String(data: data, encoding: .utf8) else { continue }
            for line in payload.split(separator: "\n") {
                guard let d = line.data(using: .utf8) else { continue }
                do {
                    let cmd = try JSONDecoder().decode(AppCommand.self, from: d)
                    let h = handler
                    Task { @MainActor in h(cmd) }
                } catch {
                    fputs("osmium: \(error)\n", stderr)
                }
            }
        }
    }
}

final class App: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var server: CommandServer?
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var controller: MainController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
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

        let mc = MainController()
        controller = mc
        let v = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        let ww = min(max(v.width * 0.86, 1180), 1680)
        let hh = min(max(v.height * 0.88, 760), 1120)
        let w = ShellWindow(
            contentRect: NSRect(x: v.midX - ww / 2, y: v.midY - hh / 2, width: ww, height: hh),
            styleMask: [.borderless, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = false
        w.collectionBehavior = [.fullScreenNone]
        w.minSize = NSSize(width: 1180, height: 760)
        w.contentViewController = mc
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        let srv = CommandServer(socketURL: osmDir.appendingPathComponent("osmium.sock")) { [weak self] cmd in
            self?.controller?.apply(cmd)
        }
        do {
            try srv.start()
            server = srv
        } catch {
            fputs("osmium socket failed: \(error)\n", stderr)
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.controller?.handleModifierFlags(e.modifierFlags)
            return e
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            (self?.controller?.handleShortcut(event: e) == true) ? nil : e
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let mc = self?.controller, !mc.hasTabs else { return }
            mc.apply(AppCommand(type: "open-terminal", cwd: FileManager.default.currentDirectoryPath, path: nil, url: nil, event: nil, command: nil))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.controller?.focusSurface()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller?.focusSurface()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        server?.stop()
    }
}
