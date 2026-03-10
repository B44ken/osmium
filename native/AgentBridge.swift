import Foundation

struct AgentBridgeExit {
    let completed: Bool
    let cancelled: Bool
    let stderrText: String?
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
}

private final class AgentModelLoadCallback: @unchecked Sendable {
    let run: ([AgentModelOption]) -> Void

    init(_ run: @escaping ([AgentModelOption]) -> Void) {
        self.run = run
    }
}

private final class AgentThreadsLoadCallback: @unchecked Sendable {
    let run: ([AgentThreadSummary]) -> Void

    init(_ run: @escaping ([AgentThreadSummary]) -> Void) {
        self.run = run
    }
}

private final class AgentThreadLoadCallback: @unchecked Sendable {
    let run: (AgentThreadSnapshot?) -> Void

    init(_ run: @escaping (AgentThreadSnapshot?) -> Void) {
        self.run = run
    }
}

enum AgentBridge {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func loadModels(cwd: String, completion: @escaping ([AgentModelOption]) -> Void) {
        let callback = AgentModelLoadCallback(completion)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = makeProcess(arguments: ["--cwd", cwd, "--list-models"])
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            try! process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return }
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let options = decodeEvents(output)
                .compactMap(\.models)
                .flatMap { $0 }
                .prefix(9)
                .enumerated()
                .map { index, model in
                    AgentModelOption(
                        index: index + 1,
                        model: model.model,
                        displayName: model.displayName,
                        isDefault: model.isDefault
                    )
                }

            OperationQueue.main.addOperation {
                callback.run(Array(options))
            }
        }
    }

    static func loadRecentThreads(cwd: String, completion: @escaping ([AgentThreadSummary]) -> Void) {
        let callback = AgentThreadsLoadCallback(completion)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = makeProcess(arguments: ["--cwd", cwd, "--list-threads"])
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                OperationQueue.main.addOperation {
                    callback.run([])
                }
                return
            }

            guard process.terminationStatus == 0 else {
                OperationQueue.main.addOperation {
                    callback.run([])
                }
                return
            }

            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let threads = decodeEvents(output)
                .compactMap(\.threads)
                .flatMap { $0 }

            OperationQueue.main.addOperation {
                callback.run(threads)
            }
        }
    }

    static func loadThreadSnapshot(
        cwd: String,
        threadId: String,
        completion: @escaping (AgentThreadSnapshot?) -> Void
    ) {
        let callback = AgentThreadLoadCallback(completion)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = makeProcess(arguments: ["--cwd", cwd, "--read-thread", threadId])
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                OperationQueue.main.addOperation {
                    callback.run(nil)
                }
                return
            }

            guard process.terminationStatus == 0 else {
                OperationQueue.main.addOperation {
                    callback.run(nil)
                }
                return
            }

            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let thread = decodeEvents(output)
                .compactMap(\.thread)
                .first

            OperationQueue.main.addOperation {
                callback.run(thread)
            }
        }
    }

    static func makeTurnTask(
        cwd: String,
        prompt: String,
        effort: AgentReasoningPreset,
        model: String?,
        threadId: String?
    ) -> AgentBridgeTask {
        var arguments = ["--cwd", cwd, "--prompt", prompt, "--effort", effort.rawValue]
        if let model { arguments += ["--model", model] }
        if let threadId { arguments += ["--thread-id", threadId] }
        return AgentBridgeTask(process: makeProcess(arguments: arguments))
    }

    static func decodeLine(_ line: String) -> AgentBridgeEvent {
        try! JSONDecoder().decode(AgentBridgeEvent.self, from: Data(line.utf8))
    }

    static func decodeEvents(_ output: String) -> [AgentBridgeEvent] {
        output.split(separator: "\n").map { decodeLine(String($0)) }
    }

    static func makeProcess(arguments: [String]) -> Process {
        let bridgePath = root.appendingPathComponent("src/agent/bridge.ts").path
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["BUN"] ?? NSHomeDirectory() + "/.bun/bin/bun"
        )
        process.currentDirectoryURL = root
        process.arguments = ["run", bridgePath] + arguments
        return process
    }
}

final class AgentBridgeTask: @unchecked Sendable {
    var onEvent: ((AgentBridgeEvent) -> Void)?
    var onExit: ((AgentBridgeExit) -> Void)?

    private let process: Process
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var completed = false
    private var cancelled = false

    init(process: Process) {
        self.process = process
    }

    func start() throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading

        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            let task = self
            OperationQueue.main.addOperation {
                task.consumeStdout(data)
            }
        }

        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            let task = self
            OperationQueue.main.addOperation {
                task.stderrBuffer.append(data)
            }
        }

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let task = self
            OperationQueue.main.addOperation {
                task.finish(process)
            }
        }

        try process.run()
    }

    func cancel() {
        cancelled = true
        process.terminate()
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.prefix(upTo: newline)
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty, let text = String(data: line, encoding: .utf8) else { continue }
            let event = AgentBridge.decodeLine(text)
            if event.type == "completed" || event.type == "error" {
                completed = true
            }
            onEvent?(event)
        }
    }

    private func finish(_ process: Process) {
        let stderrText = String(data: stderrBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        onExit?(AgentBridgeExit(
            completed: completed,
            cancelled: cancelled,
            stderrText: stderrText?.isEmpty == false ? stderrText : nil,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        ))
    }
}
