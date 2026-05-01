import AppKit
import SwiftUI

@Observable
final class Tabs {
    enum TabType: String { case terminal = "term", editor = "edit", web, agent }
    struct Tab { var id: String, type: TabType, title: String, view: any View }
    var list: [Tab] = []
    var curId: String? = nil
    var cur: Tab? { curId != nil ? list.first(where: { $0.id == curId! }) : nil }

    func swap(off: Int) {
        let find = self.list.firstIndex(where: { $0.id == self.curId! })!
        self.curId = list[(find + off + list.count) % list.count].id
    }
}

@MainActor
final class Osmium {
    var tabs = Tabs(), keyb = Keyboard(), pipe = Pipe()

    func readPipe() {
        guard let c = self.pipe.getOne(), c.cmd == "new" else { return }
        Task { await MainActor.run {
            guard !self.tabs.list.contains(where: { $0.id == c.id! }) else { return }
            self.newTab(type: Tabs.TabType(rawValue: c.type!)!, path: c.path!, id: c.id!)
        }}
        Task { try? await Task.sleep(nanoseconds: UInt64(2e6)) }
    }

    func newTab(type: Tabs.TabType, path: String, id: String) {
        if(type == .terminal) {
            self.tabs.list.append(Tabs.Tab(id: id, type: type, title: path, view: Terminal()))
            self.tabs.curId = id
        }
    }

    init() {
        setupMenu()
        let window = GlassWindow(size: CGSize(width: 900, height: 600), radius: 12)
        window.host(ZStack { Viewer(tabs: tabs); Sidebar(tabs: tabs, keyboard: keyb) })

        Thread { while true { self.readPipe() } }.start()

        keyb.on("opt n", { self.newTab(type: .terminal, path: "~", id: UUID().uuidString) })
        keyb.on("opt ]", { self.tabs.swap(off: -1) })
        keyb.on("opt [", { self.tabs.swap(off: 1) })
        
        NSApp.activate(ignoringOtherApps: true)
        NSApp.run()
    }
}