import AppKit
import SwiftUI

final class GlassView: NSVisualEffectView {
    init(radius: CGFloat = 12, behind: Bool = false, bordered: Bool = false) {
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = behind ? .behindWindow : .withinWindow
        state = .active
        wantsLayer = true
        layer!.cornerRadius = radius
        layer!.cornerCurve = .continuous
        if bordered {
            layer!.borderWidth = 1
            layer!.borderColor = NSColor(white: 1, alpha: 0.16).cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class GlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(size: CGSize, radius: CGFloat = 12) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered, defer: false
        )
        center()
        isOpaque = false
        backgroundColor = .clear
        contentView = GlassView(radius: radius, behind: true)
        makeKeyAndOrderFront(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let b = contentView?.bounds {
            let resize = !b.insetBy(dx: 4, dy: 4).contains(event.locationInWindow)
            let drag = !b.insetBy(dx: 12, dy: 12).contains(event.locationInWindow)
            if drag && !resize {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    func host(_ view: some View) {
        let h = NSHostingView(rootView: view)
        h.frame = contentView!.bounds
        h.autoresizingMask = [.width, .height]
        contentView!.addSubview(h)
    }
}

struct GlassBg: NSViewRepresentable {
    var radius: CGFloat = 12
    func makeNSView(context: Context) -> GlassView { GlassView(radius: radius, bordered: true) }
    func updateNSView(_ v: GlassView, context: Context) {}
}

func setupMenu() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let quit = NSMenu()
    quit.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
    let bar = NSMenu()
    let item = NSMenuItem()
    item.submenu = quit
    bar.addItem(item)
    app.mainMenu = bar
}