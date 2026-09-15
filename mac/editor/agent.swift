import Foundation
import SwiftUI

func alog(_ s: String) { print("[agent \(Date().ISO8601Format())] \(s)") }   // stdout → log.txt (see main.swift)

@MainActor @Observable
final class AgentSession {
    enum Kind: String, Codable { case user, assistant, tool, error }
    struct Row: Identifiable, Codable {
        let id = UUID()
        let kind: Kind
        var text: String
        enum CodingKeys: String, CodingKey { case kind, text }
    }

    enum ButtonState { case send, pending, thinking }
    struct Opt: Identifiable { let id = UUID(); let label, desc: String }
    struct Question: Identifiable { let id = UUID(); let text, header: String; let options: [Opt]; let multi: Bool }

    var rows: [Row] = []
    var buttonState: ButtonState = .send
    var ask: (id: String, name: String)? = nil
    var askq: (id: String, questions: [Question])? = nil
    var unseen = false      // turn finished while this tab wasn't being viewed
    var viewing = false     // AgentSurface visible (i.e. current tab)

    var busy: Bool { buttonState != .send }

    private let proc = Process()
    private let stdin = Foundation.Pipe()
    private var buf = Data()

    private var chatId = ""      // our chat id (== tab id), names the transcript we own
    private var sessionId = ""   // the backend's own id, replayed back to it on resume
    private var spec = ""        // provider/model this chat was started with
    private var cwd = ""

    private static let bridge = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "core/agent/index.ts").path

    func start(cwd: String, id: String, chat: PastChat? = nil) {
        let dir = ((cwd.isEmpty ? "~" : cwd) as NSString).expandingTildeInPath
        chatId = id
        self.cwd = dir
        if let chat { rows = Chats.rows(chat); sessionId = chat.session; spec = chat.spec }
        let stdout = Foundation.Pipe()
        proc.executableURL = URL(filePath: "/bin/zsh")
        proc.currentDirectoryURL = URL(filePath: dir)   // agent.ts uses process.cwd()
        proc.arguments = ["-ilc", "exec bun '\(Self.bridge)' '\(dir)' '\(sessionId)' '\(spec)'"]   // -i: source ~/.zshrc for the user's PATH (bun, etc.)
        alog("start cwd=\(dir) resume=\(sessionId) spec=\(spec) rows=\(rows.count)")
        proc.standardInput = stdin
        proc.standardOutput = stdout
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ingest(d) } }  // FIFO order; Task{} can reorder chunks → corrupts the line buffer
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                alog("terminated code=\(p.terminationStatus)")
                self?.buttonState = .send
                self?.rows.append(Row(kind: .error, text: "agent exited (code \(p.terminationStatus))"))
            }
        }
        try! proc.run()
    }

    func stop() { send(["t": "stop"]) }   // interrupt the turn; bridge stays alive

    func say(_ text: String) {
        rows.append(Row(kind: .user, text: text))
        buttonState = .pending
        send(["t": "say", "text": text])
    }

    func answer(_ allow: Bool) {
        guard let a = ask else { return }
        send(["t": "perm", "id": a.id, "allow": allow])
        ask = nil
    }

    func answerQuestions(_ picks: [String: [String]]) {
        guard let a = askq else { return }
        send(["t": "answer", "id": a.id, "answers": picks.mapValues { $0.joined(separator: ", ") }])
        askq = nil
    }

    private func send(_ obj: [String: Any]) {
        alog("send \(obj) running=\(proc.isRunning)")
        guard proc.isRunning else {
            buttonState = .send
            rows.append(Row(kind: .error, text: "agent not running"))
            return
        }
        let d = try! JSONSerialization.data(withJSONObject: obj)
        stdin.fileHandleForWriting.write(d)
        stdin.fileHandleForWriting.write(Data([0x0a]))
    }

    private func ingest(_ d: Data) {
        buf.append(d)
        while let nl = buf.firstIndex(of: 0x0a) {
            let line = buf[buf.startIndex..<nl]
            buf.removeSubrange(buf.startIndex...nl)
            let ev = try! JSONSerialization.jsonObject(with: line) as! [String: Any]
            let t = ev["t"] as! String
            handle(t, ev)
        }
    }

    private func handle(_ t: String, _ ev: [String: Any]) {
        if t != "delta" { alog("recv \(ev)") }
        switch t {
        case "delta":
            buttonState = .thinking
            let think = ev["think"] as? String ?? ""
            let response = ev["response"] as? String ?? ""
            if think.isEmpty && response.isEmpty { return }

            let text = think.isEmpty ? response : think
            if case .assistant = rows.last?.kind {
                rows[rows.count - 1].text += text
            } else {
                rows.append(Row(kind: .assistant, text: text))
            }
        case "tool":
            buttonState = .thinking   // leave .pending on first part of any kind
            rows.append(Row(kind: .tool, text: Chats.toolLine(ev["name"] as? String ?? "tool", ev["input"])))
        case "ask":
            ask = (ev["id"] as? String ?? "", ev["name"] as? String ?? "tool")
        case "askq":
            buttonState = .thinking
            askq = (ev["id"] as? String ?? "", (ev["questions"] as? [[String: Any]] ?? []).map {
                Question(text: $0["question"] as? String ?? "", header: $0["header"] as? String ?? "",
                         options: ($0["options"] as? [[String: Any]] ?? []).map { Opt(label: $0["label"] as? String ?? "", desc: $0["description"] as? String ?? "") },
                         multi: $0["multiSelect"] as? Bool ?? false)
            })
        case "end":
            buttonState = .send
            if !viewing { unseen = true }
            if ev["error"] as? Bool == true { rows.append(Row(kind: .error, text: "turn failed")) }
            Chats.save(id: chatId, session: sessionId, spec: spec, cwd: cwd, rows: rows)
        case "session":
            sessionId = ev["id"] as? String ?? ""
            spec = ev["spec"] as? String ?? ""
        default: break
        }
    }
}

struct PastChat: Identifiable {
    let id: String
    let title: String
    let date: Date
    let cwd: String
    let session: String   // backend's own id, passed back to the bridge to resume
    let spec: String      // provider/model, so a chat resumes on the backend that created it
    let legacy: Bool      // pre-dates our own transcripts; rows come from ~/.claude
}

@MainActor enum Chats {
    // we keep our own transcripts: every backend stores history differently (claude writes jsonl,
    // copilot keeps a sqlite store), and only the backend's session id is worth asking it for.
    static let dir = URL(filePath: ("~/.osm/chats" as NSString).expandingTildeInPath)

    struct Stored: Codable {
        let id, session, spec, cwd, title: String
        let updated: Date
        let rows: [AgentSession.Row]
    }

    private static let coder = (enc: { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }(),
                                dec: { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }())

    static func save(id: String, session: String, spec: String, cwd: String, rows: [AgentSession.Row]) {
        guard let title = rows.first(where: { $0.kind == .user })?.text else { return }   // nothing said yet
        let s = Stored(id: id, session: session, spec: spec, cwd: cwd,
                       title: String(title.prefix(80)), updated: Date(), rows: rows)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! coder.enc.encode(s).write(to: dir.appending(path: "\(id).json"), options: .atomic)
    }

    static func list(cwd: String) -> [PastChat] {
        let want = ((cwd.isEmpty ? "~" : cwd) as NSString).expandingTildeInPath
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let ours = files.filter { $0.pathExtension == "json" }
            .map { try! coder.dec.decode(Stored.self, from: Data(contentsOf: $0)) }   // written atomically, so never half-parsed
            .filter { $0.cwd == want }
            .map { PastChat(id: $0.id, title: $0.title, date: $0.updated, cwd: $0.cwd,
                            session: $0.session, spec: $0.spec, legacy: false) }
        let taken = Set(ours.map(\.id))   // a resumed legacy chat now lives in both stores; ours wins
        return (ours + claudeList(cwd: cwd).filter { !taken.contains($0.id) }).sorted { $0.date > $1.date }
    }

    static func rows(_ chat: PastChat) -> [AgentSession.Row] {
        if chat.legacy { return claudeRows(cwd: chat.cwd, id: chat.id) }
        let url = dir.appending(path: "\(chat.id).json")
        return try! coder.dec.decode(Stored.self, from: Data(contentsOf: url)).rows
    }

    // --- transcripts written by claude before we kept our own ---

    static func projectDir(_ cwd: String) -> URL {
        let dir = ((cwd.isEmpty ? "~" : cwd) as NSString).expandingTildeInPath
        let slug = String(dir.map { $0 == "/" || $0 == "." ? "-" : $0 })
        return URL(filePath: ("~/.claude/projects" as NSString).expandingTildeInPath).appending(
            path: slug)
    }

    static func claudeList(cwd: String) -> [PastChat] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: projectDir(cwd), includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.compactMap { url -> PastChat? in
            guard let title = firstPrompt(url) else { return nil }  // skip transcripts with no user text
            let date =
                (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate)
                ?? .distantPast
            let id = url.deletingPathExtension().lastPathComponent
            return PastChat(id: id, title: title, date: date, cwd: cwd,
                            session: id, spec: "", legacy: true)   // empty spec → bridge falls back to osm.yaml
        }
    }

    static func firstPrompt(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        for line in ((try? h.read(upToCount: 128 << 10)) ?? Data()).split(separator: 0x0a) {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                o["type"] as? String == "user", let t = text(o["message"])
            else { continue }
            return String(t.prefix(80))
        }
        return nil
    }

    static func claudeRows(cwd: String, id: String) -> [AgentSession.Row] {
        let url = projectDir(cwd).appending(path: "\(id).jsonl")
        guard let body = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [AgentSession.Row] = []
        for line in body.split(separator: "\n") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let kind = o["type"] as? String, kind == "user" || kind == "assistant",
                let m = o["message"] as? [String: Any]
            else { continue }
            let speaker: AgentSession.Kind = kind == "user" ? .user : .assistant
            if let s = m["content"] as? String {
                if !s.isEmpty { out.append(.init(kind: speaker, text: s)) }
                continue
            }
            for b in m["content"] as? [[String: Any]] ?? [] {
                switch b["type"] as? String {
                case "text":     if let t = b["text"] as? String, !t.isEmpty { out.append(.init(kind: speaker, text: t)) }
                case "tool_use": out.append(.init(kind: .tool, text: toolLine(b["name"] as? String ?? "tool", b["input"])))
                default: break
                }
            }
        }
        return out
    }

    static func toolLine(_ name: String, _ input: Any?) -> String {
        let d = input as? [String: Any] ?? [:]
        let preview = ["command", "file_path", "path", "pattern", "url", "query"].compactMap { d[$0] as? String }.first ?? ""
        let line = preview.isEmpty ? name : "[\(name)] \(preview.replacingOccurrences(of: "\n", with: " "))"
        return String(line.prefix(120))
    }

    static func text(_ message: Any?) -> String? {
        guard let m = message as? [String: Any] else { return nil }
        if let s = m["content"] as? String { return s.isEmpty ? nil : s }
        let texts = (m["content"] as? [[String: Any]] ?? [])
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }
}

struct AgentSurface: View {
    @Bindable var session: AgentSession
    let active: Bool
    @State private var input = ""
    @State private var atBottom = true
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(session.rows) { RowView(row: $0) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .font(.system(size: Fonts.shared.size(.agent))).textSelection(.enabled)
                }.onScrollGeometryChange(for: Bool.self) {
                    $0.contentOffset.y >= $0.contentSize.height - $0.containerSize.height - 24
                } action: { _, v in atBottom = v }
                .onChange(of: session.rows.last?.text) {
                    if atBottom, let l = session.rows.last { proxy.scrollTo(l.id, anchor: .bottom) }
                }.onAppear {
                    if let l = session.rows.last { DispatchQueue.main.async { proxy.scrollTo(l.id, anchor: .bottom) } }
                }
            }

            if let ask = session.ask {
                HStack(spacing: 8) {
                    Text("allow \(ask.name)?").foregroundStyle(.white)
                    Spacer()
                    Button("deny") { session.answer(false) }
                    Button("allow") { session.answer(true) }.keyboardShortcut(.defaultAction)
                }.padding(8).background(.white.opacity(0.06))
            }

            if let q = session.askq {
                QuestionForm(questions: q.questions, onSubmit: session.answerQuestions,
                             onCancel: { session.stop(); session.askq = nil })
            }

            HStack(spacing: 8) {
                TextField("message", text: $input).textFieldStyle(.plain).onSubmit(sendOrStop).focused($inputFocused)
                let buttonText = switch session.buttonState {
                case .send: "send"
                case .pending: "pending"
                case .thinking: "thinking"
                }
                Button(buttonText, action: sendOrStop)
            }.padding(8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
        }.padding(.horizontal, 8).padding(.bottom, 8)
            // every tab stays mounted, so "being viewed" tracks the current tab, not appearance
            .onChange(of: active, initial: true) { _, on in
                session.viewing = on
                if on { session.unseen = false; DispatchQueue.main.async { inputFocused = true } }
            }
    }

    private func sendOrStop() {
        if session.buttonState != .send { session.stop(); return }
        let msg = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty { return }
        session.say(msg)
        input = ""
    }

    struct QuestionForm: View {
        let questions: [AgentSession.Question]
        let onSubmit: ([String: [String]]) -> Void
        let onCancel: () -> Void
        @State private var picks: [String: Set<String>] = [:]   // keyed by question text → selected labels

        var complete: Bool { questions.allSatisfy { !(picks[$0.text] ?? []).isEmpty } }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(questions) { q in
                    if !q.header.isEmpty { Text(q.header).font(.caption).foregroundStyle(.white.opacity(0.6)) }
                    Text(q.text).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        ForEach(q.options) { opt in
                            let on = picks[q.text]?.contains(opt.label) ?? false
                            Button { toggle(q, opt.label) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.label)
                                    if !opt.desc.isEmpty { Text(opt.desc).font(.caption).foregroundStyle(.white.opacity(0.55)) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.borderedProminent).tint(on ? .blue : .gray)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("cancel", action: onCancel)
                    Button("submit") { onSubmit(picks.mapValues(Array.init)) }
                        .disabled(!complete).keyboardShortcut(.defaultAction)
                }
            }.padding(8).background(.white.opacity(0.06))
        }

        func toggle(_ q: AgentSession.Question, _ opt: String) {
            var s = picks[q.text] ?? []
            if q.multi { if !s.insert(opt).inserted { s.remove(opt) } } else { s = [opt] }
            picks[q.text] = s
        }
    }

    struct RowView: View {
        let row: AgentSession.Row
        var body: some View {
            switch row.kind {
            case .user:
                Text(row.text).foregroundStyle(.white).padding(8)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .assistant:
                Text(.init(row.text)).foregroundStyle(.white).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .tool:
                Text(row.text).font(.custom(cfg.font.mono, size: Fonts.shared.size(.agent)))
                    .foregroundStyle(.white.opacity(0.7)).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .error:
                Text(row.text).foregroundStyle(.red.opacity(0.7))
            }
        }
    }
}
