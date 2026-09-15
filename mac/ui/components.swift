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
    @State private var browser = Files.Browser()

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach($tabs.list, id: \.id) { $tab in
                    row(tilde(tab.title), selected: tabs.curId == tab.id, trailing: { statusDot(tab) }) { tabs.curId = tab.id }
                }
                if tabs.cur?.type == .agent {
                    if !past.isEmpty {
                        heading("PAST CHATS")
                        ForEach(past) { chat in row(chat.title, selected: false) { onPick(chat) } }
                    }
                } else if !browser.dir.isEmpty {
                    heading("FILES")
                    if !browser.atRoot { row("../", selected: false, dim: true) { browser.up() } }
                    ForEach(browser.entries) { f in
                        row(f.isDir ? "\(f.name)/" : f.name, selected: false, dim: f.isDir) {
                            if f.isDir { browser.open(f.path) } else { onOpen(f.path) }
                        }
                    }
                }
            }.padding(12)
        }
        .frame(width: cfg.window.sidebar.width).frame(maxHeight: .infinity, alignment: .top)
        .background(GlassBg())
        .padding(6)
        .offset(x: keyboard.doSidebar ? 0 : -(cfg.window.sidebar.width + 12))
        .animation(.easeOut(duration: cfg.window.sidebar.slideduration), value: keyboard.doSidebar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: keyboard.doSidebar) {
            guard keyboard.doSidebar,
                  (try? await Task.sleep(for: .seconds(cfg.window.sidebar.slidedelay))) != nil else { return }
            load()
        }
        .onChange(of: tabs.curId) { if keyboard.doSidebar { load() } }   // refresh while cycling tabs
    }

    // browsing resets to the tab's live cwd on every open and tab switch: the FILES list means
    // "what's in this tab's directory", so a browsed path must not outlive the visit
    private func load() {
        tabs.syncCwd()
        guard let tab = tabs.cur else { past = []; browser = Files.Browser(); return }
        if tab.type == .agent { past = Chats.list(cwd: tab.cwd); browser = Files.Browser() }
        else { browser.open(tab.cwd); past = [] }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }

    private func row(_ text: String, selected: Bool, dim: Bool = false, _ tap: @escaping () -> Void) -> some View {
        row(text, selected: selected, dim: dim, trailing: { EmptyView() }, tap)
    }

    private func row(_ text: String, selected: Bool, dim: Bool = false,
                     @ViewBuilder trailing: () -> some View, _ tap: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }.padding(6)
            .background(.white.opacity(selected ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white.opacity(dim ? 0.4 : 1)).contentShape(Rectangle())
            .onTapGesture(perform: tap)
    }

    private func tilde(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }

    @ViewBuilder private func statusDot(_ tab: Tab) -> some View {
        if case .agent(let s) = tab.content {
            if s.busy { BreatheDot() }                                          // thinking → faint pulse
            else if s.unseen { Circle().fill(.white.opacity(0.4)).frame(width: 6, height: 6) }   // done, not yet looked at
        }
    }
}

// faint breathing dot; own view so @State resets each time it (re)appears, restarting the loop
private struct BreatheDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(.white).frame(width: 6, height: 6)
            .opacity(on ? 0.5 : 0.12)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

struct Viewer: View {
    @Bindable var tabs: Tabs
    var body: some View {
        ZStack {
            // every tab stays mounted and keeps its size: unmounting hands the view a zero frame on the
            // way back in, and swiftterm answers a 2x1 grid by reflowing the buffer away and SIGWINCHing the shell
            ForEach(tabs.list, id: \.id) { tab in
                let active = tabs.curId == tab.id
                Group {
                    switch tab.content {
                    case .terminal(let term): TermView(term: term, active: active)
                    case .web(let web):       WebView(web: web, active: active)
                    case .agent(let session): AgentSurface(session: session, active: active)
                    }
                }
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
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
    let active: Bool
    var body: some View {
        TerminalRepresentable(term: term, active: active)
            .padding(6).background(SwiftUI.Color(nsColor: OneDark.bg))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    let term: LocalProcessTerminalView
    let active: Bool
    func makeNSView(context: Context) -> LocalProcessTerminalView { term }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) { if active { focus(nsView) } }
}

struct WebView: NSViewRepresentable {
    let web: WKWebView
    let active: Bool
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ nsView: WKWebView, context: Context) { if active { focus(nsView) } }
}

