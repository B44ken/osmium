import Foundation

struct SidebarBridgeState: Codable {
    let mode: String
    let pickerQuery: String
    let pickerSelectionIndex: Int
    let pickerSource: SidebarBridgePickerSource?
}

struct SidebarBridgePickerSource: Codable {
    let kind: String
    let directory: String?
}

struct SidebarBridgeTabContext: Codable {
    let id: String
    let kind: String
    let kindPrefix: String
    let title: String
    let currentThreadId: String?
}

struct SidebarBridgeSurfaceContext: Codable {
    let kind: String
    let cwd: String
    let threadId: String?
}

struct SidebarBridgeRecentThreadContext: Codable {
    let threadId: String
    let cwd: String
    let title: String
    let preview: String
    let updatedAt: TimeInterval
}

struct SidebarBridgeContext: Codable {
    let tabs: [SidebarBridgeTabContext]
    let selectedTabId: String?
    let currentSurface: SidebarBridgeSurfaceContext
    let recentThreadsStatus: String
    let recentThreads: [SidebarBridgeRecentThreadContext]
}

struct SidebarBridgeAction: Codable {
    let type: String
    let delta: Int?
    let keyCode: Int?
    let key: String?
    let modifiers: [String]?
    let row: Int?
}

struct SidebarBridgeRow: Decodable {
    let kind: String
    let primaryText: String
    let secondaryText: String?
    let tabId: String?
    let threadId: String?
    let cwd: String?
    let path: String?
    let isActivatable: Bool
}

struct SidebarBridgeIntent: Decodable {
    let type: String
    let tabId: String?
    let threadId: String?
    let cwd: String?
    let path: String?
}

struct SidebarBridgeResult: Decodable {
    let state: SidebarBridgeState
    let rows: [SidebarBridgeRow]
    let selectionIndex: Int
    let intent: SidebarBridgeIntent?
}

struct AgentBridgeRow: Codable, Equatable {
    let id: String
    let kind: String
    let tone: String?
    let text: String?
    let activity: String?
    let title: String?
    let detail: String?
    let lines: [String]?
}

struct AgentActiveAssistant: Codable {
    let turnId: String
    let itemId: String
    let rowId: String
}

struct AgentReducerState: Codable {
    let cwd: String
    let threadId: String?
    let title: String?
    let busy: Bool
    let shouldAutoScroll: Bool
    let rows: [AgentBridgeRow]
    let activeAssistant: AgentActiveAssistant?
}

struct AgentReducerAction: Codable {
    let type: String
    let prompt: String?
    let event: AgentBridgeEvent?
    let completed: Bool?
    let cancelled: Bool?
    let stderrText: String?
    let terminationStatus: Int?
    let terminationReason: String?
    let snapshot: AgentThreadSnapshot?
    let followsBottom: Bool?
}

private struct AppBridgeRequestEnvelope<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
}

private struct SidebarReduceParams: Encodable {
    let state: SidebarBridgeState?
    let context: SidebarBridgeContext
    let action: SidebarBridgeAction
}

private struct AgentReduceParams: Encodable {
    let state: AgentReducerState?
    let cwd: String
    let action: AgentReducerAction
}

private struct SidebarBridgeResponseEnvelope: Decodable {
    struct ResultBody: Decodable {
        let sidebar: SidebarBridgeResult
    }

    let result: ResultBody?
}

private struct AgentBridgeResponseEnvelope: Decodable {
    struct ResultBody: Decodable {
        let agent: AgentReducerState
    }

    let result: ResultBody?
}

final class AppLogicBridge: @unchecked Sendable {
    static let shared = AppLogicBridge()

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private let queue = DispatchQueue(label: "osmium.app-logic-bridge")
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var nextID = 1
    private var pending: [Int: (Data?) -> Void] = [:]

    func reduceSidebar(
        state: SidebarBridgeState?,
        context: SidebarBridgeContext,
        action: SidebarBridgeAction
    ) -> SidebarBridgeResult? {
        guard let data = request(
            "sidebar/reduce",
            params: SidebarReduceParams(state: state, context: context, action: action)
        ) else {
            return nil
        }

        return try? JSONDecoder().decode(SidebarBridgeResponseEnvelope.self, from: data).result?.sidebar
    }

    func reduceAgent(
        state: AgentReducerState?,
        cwd: String,
        action: AgentReducerAction
    ) -> AgentReducerState? {
        guard let data = request(
            "agent/reduce",
            params: AgentReduceParams(state: state, cwd: cwd, action: action)
        ) else {
            return nil
        }

        return try? JSONDecoder().decode(AgentBridgeResponseEnvelope.self, from: data).result?.agent
    }

    private func request<Params: Encodable>(_ method: String, params: Params) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var output: Data?

        queue.sync {
            guard self.ensureProcessLocked() else {
                semaphore.signal()
                return
            }

            let requestID = self.nextID
            self.nextID += 1
            self.pending[requestID] = { data in
                output = data
                semaphore.signal()
            }

            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(
                AppBridgeRequestEnvelope(
                    id: requestID,
                    method: method,
                    params: params
                )
            ) else {
                self.pending.removeValue(forKey: requestID)
                semaphore.signal()
                return
            }

            var line = data
            line.append(0x0A)
            do {
                try self.stdinHandle?.write(contentsOf: line)
            } catch {
                self.pending.removeValue(forKey: requestID)
                self.stopLocked()
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 2)
        return output
    }

    private func ensureProcessLocked() -> Bool {
        if process?.isRunning == true {
            return true
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["BUN"] ?? NSHomeDirectory() + "/.bun/bin/bun"
        )
        process.currentDirectoryURL = Self.root
        process.arguments = ["run", Self.root.appendingPathComponent("src/app/bridge.ts").path]
        process.standardInput = stdin
        process.standardOutput = stdout

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            let bridge = self
            bridge.queue.async {
                bridge.consumeStdoutLocked(data)
            }
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            let bridge = self
            bridge.queue.async {
                bridge.stopLocked()
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            return false
        }

        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        return true
    }

    private func consumeStdoutLocked(_ data: Data) {
        stdoutBuffer.append(data)

        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: 0..<newline)
            stdoutBuffer.removeSubrange(0...newline)
            guard !line.isEmpty else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = json["id"] as? Int
            else {
                continue
            }
            let callback = pending.removeValue(forKey: id)
            callback?(line)
        }
    }

    private func stopLocked() {
        process?.terminationHandler = nil
        process = nil
        stdinHandle = nil
        stdoutBuffer.removeAll(keepingCapacity: false)
        let callbacks = pending.values
        pending.removeAll()
        callbacks.forEach { $0(nil) }
    }
}
