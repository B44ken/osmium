import AppKit
import WebKit
import SwiftTerm

enum TabContent {
    case terminal(LocalProcessTerminalView)
    case web(WKWebView)
    case agent(AgentSession)

    @MainActor static func makeAgent(_ cwd: String, resume: String? = nil) -> TabContent {
        let s = AgentSession()
        s.start(cwd: cwd, resume: resume)
        return .agent(s)
    }

    @MainActor static func makeTerm() -> TabContent {
        let term = LocalProcessTerminalView(frame: .zero)
        term.font = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
        term.getTerminal().setCursorStyle(.steadyBlock)
        term.caretColor = .white
        term.nativeForegroundColor = .white
        term.nativeBackgroundColor = .black
        term.startProcess(executable: "/bin/zsh", args: ["-l"], environment: Terminal.getEnvironmentVariables() + ["OSM=1"])
        return .terminal(term)
    }

    @MainActor static func makeWeb(_ url: String) -> TabContent {
        let web = WKWebView(frame: .zero)
        if let u = URL(string: url.isEmpty ? "about:blank" : url) { web.load(URLRequest(url: u)) }
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
           let dir = lsofCwd(pid) { return dir }
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

    private static func lsofCwd(_ pid: pid_t) -> String? {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/sbin/lsof")
        p.arguments = ["-a", "-d", "cwd", "-p", String(pid), "-Fn"]   // -Fn → "n<path>" lines
        let out = Foundation.Pipe(); p.standardOutput = out; p.standardError = Foundation.Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return s.split(separator: "\n").first { $0.first == "n" }.map { String($0.dropFirst()) }
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
}
