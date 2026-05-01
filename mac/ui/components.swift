import SwiftUI
import AppKit
import SwiftTerm

struct Sidebar: View {
    @Bindable var tabs: Tabs
    @Bindable var keyboard: Keyboard
    var body: some View {
        VStack(spacing: 12) {
            ForEach($tabs.list, id: \.id) { $tab in
                Text(tab.title)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(tabs.curId == tab.id ? .red : .blue, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(width: 250).frame(maxHeight: .infinity, alignment: .top)
        .background(GlassBg())
        .padding(6)
        .offset(x: keyboard.doSidebar ? 0 : -262)
        .animation(.easeOut(duration: 0.12), value: keyboard.doSidebar)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Viewer: View {
    @Bindable var tabs: Tabs
    func base() -> AnyView {
        return tabs.cur != nil ? AnyView(tabs.cur!.view) : AnyView(Text("empty"))
    }

    var body: some View {
        base().frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(tabs.curId)
            .padding(6)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            .padding(6)
    }
}

struct Terminal: NSViewRepresentable {
    let term: LocalProcessTerminalView

    init() {
        term = LocalProcessTerminalView(frame: .zero)
        term.font = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
        MainActor.assumeIsolated { term.getTerminal().setCursorStyle(.steadyBlock) }
        term.caretColor = .white
        term.nativeForegroundColor = .white
        term.nativeBackgroundColor = .black
        term.startProcess(executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView { term }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}