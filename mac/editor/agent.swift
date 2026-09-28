import Foundation
import SwiftUI
import WebKit

struct PastChat: Identifiable, Decodable { let id, title, cwd: String }

enum Chats {
    static func list(cwd: String, origin: String = "http://127.0.0.1:7224") async throws -> [PastChat] {
        var url = URLComponents(string: "\(origin)/chats")!
        url.queryItems = [URLQueryItem(name: "cwd", value: cwd)]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        return try JSONDecoder().decode([PastChat].self, from: data)
    }
}

// the native shell only hosts the page and mirrors its tab status.
@MainActor @Observable
final class AgentWeb: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let url: URL
    var busy = false
    var unseen = false
    private var active = false

    init(cwd: String, id: String, origin: String = "http://127.0.0.1:7224/") {
        var components = URLComponents(string: origin)!
        components.queryItems = [URLQueryItem(name: "cwd", value: cwd), URLQueryItem(name: "id", value: id), URLQueryItem(name: "embedded", value: "1")]
        url = components.url!
        web = WKWebView()
        super.init()
        web.configuration.userContentController.add(AgentMessages(self), name: "agent")
        web.navigationDelegate = self
        web.underPageBackgroundColor = .clear
        web.load(URLRequest(url: url))
    }

    func setActive(_ on: Bool) {
        active = on
        if on { unseen = false }
        web.evaluateJavaScript("window.osmActive?.(\(on))")
    }
    func ready() {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)!
        web.evaluateJavaScript("document.documentElement.style.setProperty('--accent', 'rgb(\(accent.redComponent * 255) \(accent.greenComponent * 255) \(accent.blueComponent * 255))')")
        setActive(active)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated { NSWorkspace.shared.open(action.request.url!); decisionHandler(.cancel) }
        else { decisionHandler(.allow) }
    }
    func close() async throws {
        var endpoint = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        endpoint.path = "/session"
        var request = URLRequest(url: endpoint.url!)
        request.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: request)
    }
}

private final class AgentMessages: NSObject, WKScriptMessageHandler {
    weak var agent: AgentWeb?
    init(_ agent: AgentWeb) { self.agent = agent }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let state = message.body as! [String: Bool]
        if state["ready"] == true { agent?.ready(); return }
        agent?.busy = state["busy"]!
        agent?.unseen = state["unseen"]!
    }
}

struct AgentSurface: View {
    let agent: AgentWeb
    let active: Bool
    var body: some View {
        WebView(web: agent.web, active: active)
            .onChange(of: active, initial: true) { _, on in agent.setActive(on) }
    }
}
