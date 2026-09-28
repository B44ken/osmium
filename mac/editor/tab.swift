import AppKit
import WebKit
import SwiftTerm

enum TabContent {
    case terminal(LocalProcessTerminalView)
    case web(WKWebView)
    case agent(AgentSession)

    @MainActor static func makeAgent(_ cwd: String, id: String, chat: PastChat? = nil) -> TabContent {
        let s = AgentSession()
        s.start(cwd: cwd, id: id, chat: chat)
        return .agent(s)
    }

    @MainActor static func makeTerm(_ cwd: String) -> TabContent {
        let term = LocalProcessTerminalView(frame: .zero)
        term.changeScrollback(10_000)
        term.font = NSFont(name: cfg.font.mono, size: Fonts.shared.size(.terminal))!
        term.getTerminal().setCursorStyle(.steadyBlock)
        term.installColors(OneDark.ansi)
        term.nativeForegroundColor = OneDark.fg
        term.nativeBackgroundColor = OneDark.bg
        term.caretColor = OneDark.cursor
        term.selectedTextBackgroundColor = OneDark.selection
        term.layer!.backgroundColor = OneDark.bg.cgColor   // swiftterm only syncs this at init, and it shows through on resize
        // hide the native scrollbar; scrollWheel handles scrolling independently
        term.subviews.compactMap { $0 as? NSScroller }.first!.isHidden = true
        term.startProcess(executable: "/bin/zsh", args: ["-l"], environment: Terminal.getEnvironmentVariables() + ["OSM=1"],
                          currentDirectory: cwd)   // without this zsh inherits the app's cwd, which is / when the CLI spawns us detached
        return .terminal(term)
    }

    @MainActor static func makeWeb(_ url: String) -> TabContent {
        let web = WKWebView(frame: .zero)
        if let u = URL(string: url.isEmpty ? "about:blank" : url) {
            if u.isFileURL { web.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent()) }
            else { web.load(URLRequest(url: u)) }
        }
        return .web(web)
    }

    @MainActor static func makeEdit(_ path: String) -> TabContent {
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return makeWeb("http://127.0.0.1:7223/?path=\(enc)")
    }
}

enum TabType: String { case terminal = "term", editor = "edit", web, agent }
struct Tab { var id: String, type: TabType, title: String, cwd: String; let content: TabContent }

@MainActor enum Files {
    struct Entry: Identifiable { let id = UUID(); let name: String, path: String; let isDir: Bool }

    static func cwd(_ tab: Tab) -> String {
        if case .terminal(let t) = tab.content, let pid = t.process?.shellPid, pid > 0,
           let dir = shellCwd(pid) { return dir }
        return tab.cwd
    }

    static func list(_ cwd: String) -> [Entry] {
        let dir = (cwd as NSString).expandingTildeInPath
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: URL(filePath: dir), includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles)) ?? []
        return urls.map { u in
            Entry(name: u.lastPathComponent, path: u.path,
                  isDir: (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }.sorted { $0.isDir != $1.isDir ? $0.isDir
                 : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // sidebar browsing state: dir and its listing move as one, so the rows can never disagree with the path
    @MainActor struct Browser {
        private(set) var dir = "", entries: [Entry] = []
        var atRoot: Bool { dir == "/" }
        mutating func open(_ path: String) { dir = (path as NSString).expandingTildeInPath; entries = Files.list(dir) }
        mutating func up() { open((dir as NSString).deletingLastPathComponent) }
    }

    // the kernel's cwd for the shell, which is what lsof -a -d cwd reads, minus the subprocess: 5µs vs 65ms
    private static func shellCwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info,
                           Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) {
            String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
        }
    }
}

@Observable
final class Tabs {
    var list: [Tab] = []
    var curId: String? = nil
    var cur: Tab? { curId != nil ? list.first(where: { $0.id == curId! }) : nil }

    func swap(off: Int) {
        let find = self.list.firstIndex(where: { $0.id == self.curId! })!
        self.curId = list[(find + off + list.count) % list.count].id
    }

    // zsh emits no OSC 7 (that's gated on TERM_PROGRAM == Apple_Terminal in /etc/zshrc), so a terminal's
    // cwd is only knowable by asking the kernel. Runs on discrete events — sidebar open, tab switch —
    // because it mutates the list, not because it's expensive.
    @MainActor func syncCwd() {
        for i in list.indices where list[i].type == .terminal {
            let dir = Files.cwd(list[i])
            if list[i].cwd != dir { list[i].cwd = dir }
            if list[i].title != dir { list[i].title = dir }
        }
    }
}
