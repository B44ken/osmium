import AppKit
import Foundation

struct AgentBridgeEvent: Decodable {
    let type: String
    let threadId: String?
    let turnId: String?
    let delta: String?
    let text: String?
    let error: String?
    let message: String?
    let title: String?
    let detail: String?
    let lines: [String]?
    let models: [AgentBridgeModel]?
    let threads: [AgentThreadSummary]?
    let thread: AgentThreadSnapshot?
}

struct AgentBridgeModel: Decodable {
    let model: String
    let displayName: String
    let isDefault: Bool
}

struct AgentThreadSummary: Decodable, Equatable {
    let threadId: String
    let cwd: String
    let title: String
    let preview: String
    let updatedAt: TimeInterval
}

struct AgentThreadSnapshot: Decodable {
    let threadId: String
    let cwd: String
    let title: String
    let items: [AgentThreadSnapshotItem]
}

struct AgentThreadSnapshotItem: Decodable {
    let kind: String
    let tone: String?
    let activity: String?
    let title: String?
    let detail: String?
    let text: String?
    let lines: [String]?
}

enum AgentMessageTone: Equatable {
    case assistant
    case user
    case status
    case error
}

enum AgentActivityKind {
    case trace
    case edit

    var label: String {
        switch self {
        case .trace: return "trace"
        case .edit: return "edit"
        }
    }
}

enum AgentReasoningPreset: String, CaseIterable {
    case low
    case medium
    case high
    case xhigh

    var key: String {
        switch self {
        case .low: return "l"
        case .medium: return "m"
        case .high: return "h"
        case .xhigh: return "x"
        }
    }

    var title: String {
        switch self {
        case .low: return "low"
        case .medium: return "med"
        case .high: return "high"
        case .xhigh: return "xhigh"
        }
    }

    static func fromSelectionKey(_ key: String) -> AgentReasoningPreset? {
        switch key {
        case "l": return .low
        case "m": return .medium
        case "h": return .high
        case "x": return .xhigh
        default: return nil
        }
    }
}

struct AgentModelOption: Equatable {
    let index: Int
    let model: String
    let displayName: String
    let isDefault: Bool

    var key: String { String(index) }
}

extension Cfg {
    func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let n = string("options.font_mono")
        return NSFont(name: n, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
