import SwiftUI
import AppKit
import WebKit
import SwiftTerm

struct Sidebar: View {
    @Bindable var tabs: Tabs
    @Bindable var keyboard: Keyboard
    var onPick: (PastChat) -> Void
    var onOpen: (String) -> Void
    @State private var past: [PastChat] = []
    @State private var files: [Files.Entry] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach($tabs.list, id: \.id) { $tab in
                    row(tab.title, selected: tabs.curId == tab.id) { tabs.curId = tab.id }
                }
                if tabs.cur?.type == .agent {
                    if !past.isEmpty {
                        heading("PAST CHATS")
                        ForEach(past) { chat in row(chat.title, selected: false) { onPick(chat) } }
                    }
                } else if !files.isEmpty {
                    heading("FILES")
                    ForEach(files) { f in
                        row(f.isDir ? "\(f.name)/" : f.name, selected: false, dim: f.isDir) {
                            if !f.isDir { onOpen(f.path) }
                        }
                    }
                }
            }.padding(12)
        }
        .frame(width: 250).frame(maxHeight: .infinity, alignment: .top)
        .background(GlassBg())
        .padding(6)
        .offset(x: keyboard.doSidebar ? 0 : -262)
        .animation(.easeOut(duration: 0.12), value: keyboard.doSidebar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: keyboard.doSidebar) { _, open in if open { load() } }
        .onChange(of: tabs.curId) { if keyboard.doSidebar { load() } }   // refresh while cycling tabs
    }

    private func load() {
        guard let tab = tabs.cur else { past = []; files = []; return }
        if tab.type == .agent { past = Chats.list(cwd: tab.cwd); files = [] }
        else { files = Files.list(Files.cwd(tab)); past = [] }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }

    private func row(_ text: String, selected: Bool, dim: Bool = false, _ tap: @escaping () -> Void) -> some View {
        Text(text).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            .background(.white.opacity(selected ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white.opacity(dim ? 0.4 : 1)).contentShape(Rectangle())
            .onTapGesture(perform: tap)
    }
}

struct Viewer: View {
    @Bindable var tabs: Tabs
    var body: some View {
        ZStack {
            ForEach(tabs.list, id: \.id) { tab in
                if tabs.curId == tab.id {
                    Group {
                        switch tab.content {
                        case .terminal(let term): TermView(term: term)
                        case .web(let web):       WebView(web: web)
                        case .agent(let session): AgentSurface(session: session)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6).background(GlassBg())
        .onChange(of: tabs.curId) { _, _ in
            switch tabs.cur?.content {
            case .terminal(let t): focus(t)
            case .web(let w):      focus(w)
            default: break
            }
        }
    }
}

@MainActor func focus(_ v: NSView, tries: Int = 8) {
    DispatchQueue.main.async {
        guard let w = v.window else { if tries > 0 { focus(v, tries: tries - 1) }; return }
        if w.firstResponder !== v { w.makeFirstResponder(v) }
    }
}

struct TermView: View {
    let term: LocalProcessTerminalView
    var body: some View {
        TerminalRepresentable(term: term)
            .padding(6).background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    let term: LocalProcessTerminalView
    func makeNSView(context: Context) -> LocalProcessTerminalView { term }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) { focus(nsView) }
}

struct WebView: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ nsView: WKWebView, context: Context) { focus(nsView) }
}

