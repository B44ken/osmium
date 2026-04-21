import AppKit
import SwiftTerm

let pad: CGFloat = 14, winWd: CGFloat = 800, winHt: CGFloat = 500

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

func buildApp() -> NSWindow {
    let qmenu = NSMenu()
    qmenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
    let bar = NSMenu()
    let item = NSMenuItem()
    item.submenu = qmenu
    bar.addItem(item)
    app.mainMenu = bar

    let w = AppWindow(contentRect: NSRect(x: 0, y: 0, width: winWd, height: winHt), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    w.center()
    w.isOpaque = false
    w.backgroundColor = .clear

    let fx = NSVisualEffectView()
    fx.material = .sidebar
    fx.blendingMode = .behindWindow
    fx.state = .active
    fx.wantsLayer = true
    fx.layer!.cornerRadius = pad
    w.contentView = fx
    return w
}

func buildSidebar(width: CGFloat = 300) -> NSView {
  let sb = NSView(frame: NSRect(x: -width, y: pad, width: width - 2*pad, height: winHt - 2*pad))
  let fx = NSVisualEffectView(frame: sb.bounds)
  fx.material = .sidebar
  fx.blendingMode = .withinWindow
  fx.state = .active
  fx.wantsLayer = true
  fx.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
  fx.autoresizingMask = [.height, .width]
  sb.addSubview(fx)
  return sb
}

func attachSidebar(win: NSWindow, sb: NSView) {
  sb.frame = NSRect(x: -sb.frame.width, y: 0, width: sb.frame.width, height: win.contentView!.frame.height)
  sb.autoresizingMask = [.height]
  win.contentView!.addSubview(sb)

  NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in
    let x = e.modifierFlags.contains(.option) ? 0.0 : -sb.frame.width
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.14
      sb.animator().setFrameOrigin(NSPoint(x: x, y: 0))
    }
    return e
  }
}

func buildTerminal(frame: NSRect) -> (container: NSView, term: LocalProcessTerminalView) {
    let container = NSView(frame: frame)
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.black.cgColor
    container.layer?.cornerRadius = pad/2
    container.layer?.masksToBounds = true
    let term = LocalProcessTerminalView(frame: container.bounds.insetBy(dx: 4, dy: 4))
    term.autoresizingMask = [.width, .height]
    term.font = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
    MainActor.assumeIsolated { term.getTerminal().setCursorStyle(.steadyBlock) }
    term.caretColor = .white
    term.nativeForegroundColor = .white
    term.nativeBackgroundColor = .black
    term.startProcess(executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    container.addSubview(term)
    return (container, term)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let w = buildApp()
let sb = buildSidebar()
let (termContainer, termView) = buildTerminal(frame: w.contentView!.bounds.insetBy(dx: pad/2, dy: pad/2))
termContainer.autoresizingMask = [.width, .height]
w.contentView!.addSubview(termContainer)
attachSidebar(win: w, sb: sb)
w.makeKeyAndOrderFront(nil)
w.makeFirstResponder(termView)
app.activate(ignoringOtherApps: true)
app.run()