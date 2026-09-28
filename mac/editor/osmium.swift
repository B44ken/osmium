import AppKit
import SwiftUI
import SwiftTerm

@MainActor
final class Osmium {
    var tabs = Tabs(), keyb = Keyboard(), pipe = Pipe()

    func readPipe() {
        guard let c = self.pipe.getOne(), c.cmd == "new" else { return }
        Task { await MainActor.run {
            guard !self.tabs.list.contains(where: { $0.id == c.id! }) else { return }
            self.newTab(type: TabType(rawValue: c.type!)!, path: c.path!, id: c.id!)
        }}
        Task { try? await Task.sleep(nanoseconds: UInt64(2e6)) }
    }

    func newTab(type: TabType, path: String, id: String) {
        let dir = type == .editor ? (path as NSString).deletingLastPathComponent : path
        let cwd = (dir as NSString).expandingTildeInPath   // zsh won't expand a literal "~" handed to it as a working directory
        let content: TabContent
        switch type {
        case .terminal: content = .makeTerm(cwd)
        case .web:      content = .makeWeb(path)
        case .agent:    content = .makeAgent(path, id: id)
        case .editor:   content = .makeEdit(path)
        }
        if case .terminal(let term) = content { term.processDelegate = self }
        tabs.list.append(Tab(id: id, type: type, title: path, cwd: cwd, content: content))
        tabs.curId = id
    }

    func resumeChat(_ chat: PastChat) {
        if tabs.list.contains(where: { $0.id == chat.id }) { tabs.curId = chat.id; return }
        newTab(type: .agent, path: chat.cwd, id: chat.id)
    }

    // opt+/opt- resizes every tab of the current tab's type; agent panes redraw off the observable
    func bumpFont(_ delta: Double) {
        guard let type = tabs.cur?.type, type != .web else { return }
        Fonts.shared.bump(type, by: delta)
        let size = Fonts.shared.size(type)
        for tab in tabs.list where tab.type == type {
            switch tab.content {
            case .terminal(let t): t.font = NSFont(name: cfg.font.mono, size: size)!
            case .web(let w):      w.evaluateJavaScript("window.osmFont(\(size))")
            case .agent(let a):    a.web.evaluateJavaScript("window.osmFont(\(size))")
            }
        }
    }

    func closeTab() {
        guard let id = tabs.curId else { return }
        if case .agent(let agent) = tabs.cur?.content {
            Task {
                do { try await agent.close() }
                catch { NSApp.presentError(error) }
            }
        }
        tabs.list.removeAll { $0.id == id }
        tabs.curId = tabs.list.last?.id
    }

    init() {
        setupMenu()
        let window = GlassWindow(radius: 12)
        window.host(ZStack {
            Viewer(tabs: tabs)
            Sidebar(tabs: tabs, keyboard: keyb,
                    onPick: { self.resumeChat($0) },
                    onOpen: { self.newTab(type: .editor, path: $0, id: UUID().uuidString) })
        })

        Thread { while true { self.readPipe() } }.start()

        keyb.on("opt t", { self.newTab(type: .terminal, path: "~", id: UUID().uuidString) })
        keyb.on("opt ]", { self.tabs.swap(off: 1) })
        keyb.on("opt [", { self.tabs.swap(off: -1) })
        keyb.on("opt w", { self.closeTab() })
        keyb.on("opt =", { self.bumpFont(1) })
        keyb.on("opt -", { self.bumpFont(-1) })

        newTab(type: .terminal, path: "~", id: UUID().uuidString)   // open with one terminal; CLI skips its inject on fresh spawn

        NSApp.activate(ignoringOtherApps: true)
        NSApp.run()
    }
}

// ctrl+d (zsh EOF → process exits) fires processTerminated on the main queue (LocalProcess default).
extension Osmium: LocalProcessTerminalViewDelegate {
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            tabs.list.removeAll { if case .terminal(let t) = $0.content { return t === source }; return false }
            if !tabs.list.contains(where: { $0.id == tabs.curId }) { tabs.curId = tabs.list.last?.id }
        }
    }
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
