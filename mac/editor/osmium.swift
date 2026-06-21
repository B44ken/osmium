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

    func newTab(type: TabType, path: String, id: String, resume: String? = nil) {
        let content: TabContent
        switch type {
        case .terminal: content = .makeTerm()
        case .web:      content = .makeWeb(path)
        case .agent:    content = .makeAgent(path, resume: resume)
        case .editor:   content = .makeEdit(path)
        }
        if case .terminal(let term) = content { term.processDelegate = self }
        let cwd = type == .editor ? (path as NSString).deletingLastPathComponent : path
        tabs.list.append(Tab(id: id, type: type, title: path, cwd: cwd, content: content))
        tabs.curId = id
    }

    func resumeChat(_ chat: PastChat) {
        if tabs.list.contains(where: { $0.id == chat.id }) { tabs.curId = chat.id; return }
        newTab(type: .agent, path: chat.cwd, id: chat.id, resume: chat.id)
    }

    func closeTab() {
        guard let id = tabs.curId else { return }
        tabs.list.removeAll { $0.id == id }
        tabs.curId = tabs.list.last?.id
    }

    init() {
        setupMenu()
        let window = GlassWindow(size: CGSize(width: 900, height: 600), radius: 12)
        window.host(ZStack {
            Viewer(tabs: tabs)
            Sidebar(tabs: tabs, keyboard: keyb,
                    onPick: { self.resumeChat($0) },
                    onOpen: { self.newTab(type: .editor, path: $0, id: UUID().uuidString) })
        })

        Thread { while true { self.readPipe() } }.start()

        keyb.on("opt n", { self.newTab(type: .terminal, path: "~", id: UUID().uuidString) })
        keyb.on("opt ]", { self.tabs.swap(off: 1) })
        keyb.on("opt [", { self.tabs.swap(off: -1) })
        keyb.on("opt w", { self.closeTab() })

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