import Foundation
import Observation
import Yams

struct Config: Decodable {
    struct Font: Decodable { let mono: String; let sans: String; let size: Double; let sizes: [String: Double] }
    struct Agent: Decodable { let permissions: String; let effort: String }
    struct Window: Decodable {
        struct Sidebar: Decodable { let width: Double; let slidedelay: Double; let slideduration: Double }
        let width: Double; let height: Double; let sidebar: Sidebar
    }
    let font: Font
    let agent: Agent
    let window: Window
}

private func deep(_ base: Any, _ over: Any) -> Any {
    guard let b = base as? [String: Any], let o = over as? [String: Any] else { return over }
    var out = b
    // an emptied key ("width:") parses as NSNull — no override, keep the repo default underneath
    for (k, v) in o where !(v is NSNull) { out[k] = b[k].map { deep($0, v) } ?? v }
    return out
}

private func read(_ url: URL) -> Any {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [String: Any]() }
    return (try! Yams.load(yaml: text)) ?? [String: Any]()
}

private let home = URL(filePath: ("~/.osm/osm.yaml" as NSString).expandingTildeInPath)

// repo osm.yaml is tracked defaults; ~/.osm/osm.yaml is this machine's overrides and keys
let cfg: Config = {
    let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "osm.yaml")
    return try! YAMLDecoder().decode(Config.self, from: Yams.dump(object: deep(read(repo), read(home))))
}()

// merge a fragment into ~/.osm/osm.yaml; every other key (the api keys) survives untouched.
// sortKeys because swift dictionaries are unordered per-process and the file would otherwise churn.
func persist(_ patch: [String: Any]) {
    try! FileManager.default.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Yams.dump(object: deep(read(home), patch), sortKeys: true).write(to: home, atomically: true, encoding: .utf8)
}

// per-pane font size, live-adjusted by opt+/opt- and persisted back to ~/.osm/osm.yaml
@MainActor @Observable
final class Fonts {
    static let shared = Fonts()
    private var sizes = cfg.font.sizes

    func size(_ type: TabType) -> Double { sizes[type.rawValue] ?? cfg.font.size }

    func bump(_ type: TabType, by delta: Double) {
        let next = min(48, max(6, (size(type) + delta).rounded()))
        sizes[type.rawValue] = next
        persist(["font": ["sizes": [type.rawValue: Int(next)]]])   // yams renders Double as 1.5e+1; Int keeps the file readable
    }
}
