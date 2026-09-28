import Foundation
import Testing
@testable import Osmium

private final class AgentServer {
    let process = Process()
    let home = FileManager.default.temporaryDirectory.appending(path: "osmium-native-test-\(UUID())")
    let origin: String

    init() throws {
        try FileManager.default.createDirectory(at: home.appending(path: ".osm/chats"), withIntermediateDirectories: true)
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = Foundation.Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.currentDirectoryURL = root
        process.arguments = ["bun", "-e", """
            import { serveAgent } from './core/agent/web/server.ts';
            const app = serveAgent({ port: 0, home: process.argv[1] });
            console.log(app.server.url.origin);
            """, home.path]
        process.standardOutput = output
        try process.run()
        origin = String(data: output.fileHandleForReading.availableData, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() { process.terminate(); process.waitUntilExit() }
    deinit {
        if process.isRunning { stop() }
        try! FileManager.default.removeItem(at: home)
    }
}

struct AgentTests {
    @Test func historyUsesAgentServer() async throws {
        let server = try AgentServer()
        let chat = """
            {"id":"native-test","title":"hello","cwd":"\(server.home.path)","updated":"2026-09-28","session":"session","spec":"claude/opus","rows":[]}
            """
        try Data(chat.utf8).write(to: server.home.appending(path: ".osm/chats/native-test.json"))
        let chats = try await Chats.list(cwd: server.home.path, origin: server.origin)
        #expect(chats.count == 1)
        #expect(chats.first?.title == "hello")
    }

    @Test func unavailableHistoryThrowsInsteadOfCrashing() async throws {
        let server = try AgentServer()
        server.stop()
        do {
            _ = try await Chats.list(cwd: server.home.path, origin: server.origin)
            Issue.record("expected a connection failure")
        } catch let error as URLError {
            #expect(error.code == .cannotConnectToHost)
        }
    }

    @Test func cancelledHistoryThrowsInsteadOfCrashing() async throws {
        let server = try AgentServer()
        let task = Task {
            withUnsafeCurrentTask { $0!.cancel() }
            return try await Chats.list(cwd: server.home.path, origin: server.origin)
        }
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        }
    }

    @Test func invalidHistoryThrowsInsteadOfCrashing() async throws {
        let server = try AgentServer()
        try Data("invalid json".utf8).write(to: server.home.appending(path: ".osm/chats/broken.json"))
        await #expect(throws: DecodingError.self) {
            try await Chats.list(cwd: server.home.path, origin: server.origin)
        }
    }
}
