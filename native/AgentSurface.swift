import AppKit
import Foundation

final class AgentSurface: Surface {
    private let initialDirectory: String
    private let scrollView = NSScrollView()
    private let feedDocument = NSView()
    private let feedStack = NSStackView()
    private let composer = AgentComposerView()
    private let selectionMenu = AgentSelectionMenuView()

    private var threadID: String?
    private var activeTurn: AgentBridgeTask?
    private var activeAssistantMessage: AgentMessageView?
    private var conversationTitle: String?
    private var shouldAutoScroll = true
    private var composerHeightConstraint: NSLayoutConstraint?

    override var titleText: String {
        conversationTitle ?? URL(fileURLWithPath: initialDirectory).lastPathComponent.ifEmpty(initialDirectory)
    }
    override var preferredFirstResponder: NSResponder? { composer.textView }
    var cwd: String { initialDirectory }

    init(cwd: String) {
        initialDirectory = cwd
        super.init(kindPrefix: "A")
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        activeTurn?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = makeRoot()
        root.wantsLayer = true
        root.layer?.backgroundColor = cfg.color("theme.panel_bg").cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(feedDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        root.addSubview(scrollView)

        feedDocument.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = feedDocument

        feedStack.orientation = .vertical
        feedStack.alignment = .leading
        feedStack.spacing = 18
        feedStack.translatesAutoresizingMaskIntoConstraints = false
        feedDocument.addSubview(feedStack)

        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.onSubmit = { [weak self] prompt in
            self?.submit(prompt: prompt)
        }
        composer.onStop = { [weak self] in
            self?.stopCurrentTurn()
        }
        composer.onPickerVisibilityChanged = { [weak self] visible in
            self?.setSelectionMenuVisible(visible)
        }
        composer.onReasoningChanged = { [weak self] reasoning in
            self?.selectionMenu.setSelectedReasoning(reasoning)
        }
        composer.onModelChanged = { [weak self] model in
            self?.selectionMenu.setSelectedModel(model?.model)
        }
        root.addSubview(composer)

        selectionMenu.translatesAutoresizingMaskIntoConstraints = false
        selectionMenu.onSelectReasoning = { [weak self] reasoning in
            self?.composer.selectReasoning(reasoning)
            self?.composer.dismissPicker()
            self?.view.window?.makeFirstResponder(self?.composer.textView)
        }
        selectionMenu.onSelectModel = { [weak self] model in
            self?.composer.selectModel(model)
            self?.composer.dismissPicker()
            self?.view.window?.makeFirstResponder(self?.composer.textView)
        }
        root.addSubview(selectionMenu)

        composerHeightConstraint = composer.heightAnchor.constraint(equalToConstant: 92)

        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            composer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            composer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            composerHeightConstraint!,

            selectionMenu.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            selectionMenu.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -14),

            feedDocument.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            feedStack.leadingAnchor.constraint(equalTo: feedDocument.leadingAnchor, constant: 28),
            feedStack.trailingAnchor.constraint(equalTo: feedDocument.trailingAnchor, constant: -28),
            feedStack.topAnchor.constraint(equalTo: feedDocument.topAnchor, constant: 22),
            feedStack.bottomAnchor.constraint(equalTo: feedDocument.bottomAnchor, constant: -24),
        ])
        composer.setBusy(false)
        selectionMenu.setSelectedReasoning(composer.reasoning)
        loadModels()
    }

    override func activate(in window: NSWindow?) {
        window?.makeFirstResponder(composer.textView)
    }

    private func submit(prompt: String) {
        guard activeTurn == nil else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if conversationTitle == nil {
            conversationTitle = Self.makeConversationTitle(from: trimmed)
            onStateChange?()
        }

        composer.clear()
        composer.setBusy(true)
        shouldAutoScroll = true

        _ = appendMessage(text: trimmed, tone: .user)
        activeAssistantMessage = nil

        let task = AgentBridge.makeTurnTask(
            cwd: initialDirectory,
            prompt: trimmed,
            effort: composer.reasoning,
            model: composer.model?.model,
            threadId: threadID
        )
        task.onEvent = { [weak self, weak task] event in
            guard let self, let task, self.activeTurn === task else { return }
            self.handleBridgeEvent(event)
        }
        task.onExit = { [weak self, weak task] result in
            guard let self, let task, self.activeTurn === task else { return }
            self.handleTurnExit(result)
        }
        activeTurn = task
        try! task.start()
        scrollToBottom(force: true)
    }

    private func stopCurrentTurn() {
        activeTurn?.cancel()
    }

    private func handleBridgeEvent(_ event: AgentBridgeEvent) {
        switch event.type {
        case "thread.started", "thread.resumed":
            if let threadId = event.threadId { threadID = threadId }
        case "turn.started":
            _ = event.turnId
        case "delta":
            if let delta = event.delta {
                let assistant = ensureAssistantMessage()
                assistant.appendText(delta)
                scrollToBottom()
            }
        case "trace":
            if let title = event.title {
                _ = appendActivity(kind: .trace, title: title, detail: event.detail, text: event.text, lines: event.lines ?? [])
                scrollToBottom()
            }
        case "edit":
            if let title = event.title {
                _ = appendActivity(kind: .edit, title: title, detail: event.detail, text: event.text, lines: event.lines ?? [])
                scrollToBottom()
            }
        case "completed":
            if let threadId = event.threadId { threadID = threadId }
            if let text = event.text, !text.isEmpty {
                let assistant = ensureAssistantMessage()
                if assistant.text.isEmpty {
                    assistant.setText(text)
                }
            }
            if let error = event.error, !error.isEmpty {
                let assistant = ensureAssistantMessage(tone: .error)
                assistant.setTone(.error)
                if assistant.text.isEmpty {
                    assistant.setText(error)
                } else {
                    assistant.appendText("\n\n\(error)")
                }
            }
            activeAssistantMessage = nil
            scrollToBottom()
        case "error":
            if let message = event.message ?? event.error {
                let assistant = ensureAssistantMessage(tone: .error)
                assistant.setTone(.error)
                assistant.setText(message)
                scrollToBottom()
            }
            activeAssistantMessage = nil
        default:
            break
        }
    }

    private func handleTurnExit(_ result: AgentBridgeExit) {
        activeTurn = nil
        composer.setBusy(false)

        if result.completed {
            return
        }

        if result.cancelled {
            if let assistant = activeAssistantMessage, !assistant.text.isEmpty {
                assistant.setTone(.status)
                assistant.setText("\(assistant.text)\n\nStopped.")
            } else {
                _ = appendMessage(text: "Stopped.", tone: .status)
            }
            activeAssistantMessage = nil
            scrollToBottom()
            return
        }

        let fallback = result.terminationReason == .exit
            ? "Agent bridge exited with status \(result.terminationStatus)."
            : "Agent bridge terminated unexpectedly."
        let message = result.stderrText ?? fallback

        if let assistant = activeAssistantMessage {
            assistant.setTone(.error)
            assistant.setText(message)
        } else {
            _ = appendMessage(text: message, tone: .error)
        }
        activeAssistantMessage = nil
        scrollToBottom()
    }

    @discardableResult
    private func appendMessage(text: String, tone: AgentMessageTone, emphasized: Bool = false) -> AgentMessageView {
        let message = AgentMessageView(text: text, tone: tone, emphasized: emphasized)
        addFeedRow(message)
        return message
    }

    @discardableResult
    private func appendActivity(
        kind: AgentActivityKind,
        title: String,
        detail: String? = nil,
        text: String? = nil,
        lines: [String] = []
    ) -> AgentActivityView {
        let view = AgentActivityView(kind: kind, title: title, detail: detail, text: text, lines: lines)
        addFeedRow(view)
        return view
    }

    private func addFeedRow(_ content: NSView) {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            content.topAnchor.constraint(equalTo: wrap.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: wrap.widthAnchor, multiplier: 0.96),
        ])

        feedStack.addArrangedSubview(wrap)
        wrap.widthAnchor.constraint(equalTo: feedStack.widthAnchor).isActive = true
    }

    private func ensureAssistantMessage(tone: AgentMessageTone = .assistant) -> AgentMessageView {
        if let message = activeAssistantMessage {
            if tone != .assistant {
                message.setTone(tone)
            }
            return message
        }

        let message = appendMessage(text: "", tone: tone)
        activeAssistantMessage = message
        return message
    }

    private func scrollToBottom(force: Bool = false) {
        guard force || shouldAutoScroll else { return }
        if force {
            shouldAutoScroll = true
        }
        DispatchQueue.main.async {
            self.view.layoutSubtreeIfNeeded()
            let documentHeight = self.feedDocument.bounds.height
            let viewportHeight = self.scrollView.contentView.bounds.height
            let point = NSPoint(x: 0, y: max(documentHeight - viewportHeight, 0))
            self.scrollView.contentView.scroll(to: point)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    @objc private func feedDidScroll(_ notification: Notification) {
        shouldAutoScroll = isNearBottom()
    }

    private func isNearBottom(tolerance: CGFloat = 36) -> Bool {
        view.layoutSubtreeIfNeeded()
        let documentHeight = feedDocument.bounds.height
        let viewport = scrollView.contentView.bounds
        return viewport.maxY >= documentHeight - tolerance
    }

    private func setSelectionMenuVisible(_ visible: Bool) {
        if visible {
            selectionMenu.alphaValue = 0
            selectionMenu.isHidden = false
            animate(0.12) {
                self.selectionMenu.animator().alphaValue = 1
            }
            return
        }

        guard !selectionMenu.isHidden else { return }
        animate(0.12) {
            self.selectionMenu.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, !self.composer.isPickerVisible else { return }
            self.selectionMenu.isHidden = true
        }
    }

    private func loadModels() {
        AgentBridge.loadModels(cwd: initialDirectory) { [weak self] options in
            guard let self else { return }
            self.composer.setModels(options)
            self.selectionMenu.setModels(options)
            self.selectionMenu.setSelectedModel(self.composer.model?.model)
        }
    }

    private static func makeConversationTitle(from prompt: String) -> String {
        let collapsed = prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "chat" }
        let limit = 44
        guard collapsed.count > limit else { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<index])…"
    }
}
