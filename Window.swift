import AppKit

final class AppWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let bounds = contentView?.bounds {
            let p = event.locationInWindow
            if p.x <= 4 || p.y <= 4 || p.x >= bounds.maxX - 4 || p.y >= bounds.maxY - 4 {
                super.sendEvent(event); return
            } else if !bounds.insetBy(dx: 12, dy: 12).contains(p) {
                performDrag(with: event); return
            }
        }
        super.sendEvent(event)
    }
}

final class Window {
    let pad: CGFloat
    let nsWindow: AppWindow
    private var panels: [NSView] = []
    private(set) var sidebar: Sidebar?

    init(width: CGFloat, height: CGFloat, pad: CGFloat) {
        self.pad = pad

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let quit = NSMenu()
        quit.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        let bar = NSMenu()
        let item = NSMenuItem()
        item.submenu = quit
        bar.addItem(item)
        app.mainMenu = bar

        nsWindow = AppWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .resizable],
            backing: .buffered, defer: false
        )
        nsWindow.center()
        nsWindow.isOpaque = false
        nsWindow.backgroundColor = .clear

        let fx = NSVisualEffectView()
        fx.material = .sidebar
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer!.cornerRadius = pad
        fx.layer!.cornerCurve = .continuous
        nsWindow.contentView = fx
    }

    func addPanel(_ view: NSView) {
        let cv = nsWindow.contentView!
        view.frame = cv.bounds.insetBy(dx: pad / 2, dy: pad / 2)
        view.autoresizingMask = [.width, .height]
        cv.addSubview(view)
        panels.append(view)
    }

    func addSidebar(_ s: Sidebar) {
        sidebar = s
    }

    func run() {
        nsWindow.makeKeyAndOrderFront(nil)
        if let first = panels.first(where: { $0.acceptsFirstResponder }) {
            nsWindow.makeFirstResponder(first)
        }
        sidebar?.attach(to: nsWindow.contentView!)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.run()
    }
}

final class Sidebar: NSView {
    private let effect: NSVisualEffectView
    private let width: CGFloat
    private let inset: CGFloat

    private let label: NSTextField

    init(width: CGFloat = 240, pad: CGFloat, inset: CGFloat) {
        self.width = width
        self.inset = inset
        effect = NSVisualEffectView(frame: .zero)
        label = NSTextField(wrappingLabelWithString: "")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.zPosition = 100

        effect.material = .sidebar
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = pad
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor(white: 1, alpha: 0.16).cgColor
        effect.autoresizingMask = [.height, .width]
        addSubview(effect)

        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = NSColor(white: 1, alpha: 0.7)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.autoresizingMask = [.width]
        effect.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        DispatchQueue.main.async {
            self.label.stringValue = text
            self.label.sizeToFit()
        }
    }

    func attach(to host: NSView) {
        let h = host.bounds.height
        frame = NSRect(x: -width, y: inset, width: width, height: h - inset * 2)
        effect.frame = bounds
        label.frame = NSRect(x: 8, y: bounds.height - 24, width: bounds.width - 16, height: 20)
        autoresizingMask = [.height]
        host.addSubview(self, positioned: .above, relativeTo: nil)

        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard let self else { return e }
            let x = e.modifierFlags.contains(.option) ? self.inset : -self.width
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                self.animator().setFrameOrigin(NSPoint(x: x, y: self.inset))
            }
            return e
        }
    }
}
