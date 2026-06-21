import Foundation
import Yams

struct Config: Decodable {
    struct Font: Decodable { let mono: String; let sans: String; let size: Double }
    struct Agent: Decodable { let permissions: String; let effort: String }
    let font: Font
    let agent: Agent
}

let cfg: Config = {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "osm.yaml")
    return try! YAMLDecoder().decode(Config.self, from: String(contentsOf: url, encoding: .utf8))
}()
