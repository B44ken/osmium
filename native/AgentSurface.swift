import AppKit
import Foundation

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class AgentSurface: Surface {
    private var currentDirectory: String
    private let scrollView = NSScrollView()
    private let feedDocument = FlippedDocumentView()
    private let feedStack = NSStackView()
    private let composer = AgentComposerView()
    private let selectionMenu = AgentSelectionMenuView()

    private var activeTurn: AgentBridgeTask?
    private var composerHeightConstraint: NSLayoutConstraint?
    private var modelLoadGeneration = 0
    private var agentState: AgentReducerState?

    override var titleText: String {
        agentState?.title ?? URL(fileURLWithPath: currentDirectory).lastPathComponent.ifEmpty(currentDirectory)
    }
    override var preferredFirstResponder: NSResponder? { composer.textView }
    var cwd: String { currentDirectory }
    var currentThreadID: String? { agentState?.threadId }

    init(cwd: String) {
        currentDirectory = cwd
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

        composer.clear()
        _ = reduceAgent(action: AgentReducerAction(
            type: "submit",
            prompt: trimmed,
            event: nil,
            completed: nil,
            cancelled: nil,
            stderrText: nil,
            terminationStatus: nil,
            terminationReason: nil,
            snapshot: nil,
            followsBottom: nil
        ))

        let task = AgentBridge.makeTurnTask(
            cwd: currentDirectory,
            prompt: trimmed,
            effort: composer.reasoning,
            model: composer.model?.model,
            threadId: agentState?.threadId
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
    }

    private func stopCurrentTurn() {
        activeTurn?.cancel()
    }

    private func handleBridgeEvent(_ event: AgentBridgeEvent) {
        _ = reduceAgent(action: AgentReducerAction(
            type: "bridgeEvent",
            prompt: nil,
            event: event,
            completed: nil,
            cancelled: nil,
            stderrText: nil,
            terminationStatus: nil,
            terminationReason: nil,
            snapshot: nil,
            followsBottom: nil
        ))
    }

    private func handleTurnExit(_ result: AgentBridgeExit) {
        activeTurn = nil
        _ = reduceAgent(action: AgentReducerAction(
            type: "turnExit",
            prompt: nil,
            event: nil,
            completed: result.completed,
            cancelled: result.cancelled,
            stderrText: result.stderrText,
            terminationStatus: Int(result.terminationStatus),
            terminationReason: result.terminationReason == .exit ? "exit" : "uncaughtSignal",
            snapshot: nil,
            followsBottom: nil
        ))
    }

    func replaceThread(with snapshot: AgentThreadSnapshot) {
        activeTurn?.cancel()
        activeTurn = nil

        composer.clear()
        _ = reduceAgent(action: AgentReducerAction(
            type: "replaceThread",
            prompt: nil,
            event: nil,
            completed: nil,
            cancelled: nil,
            stderrText: nil,
            terminationStatus: nil,
            terminationReason: nil,
            snapshot: snapshot,
            followsBottom: nil
        ))
        loadModels()
    }

    @discardableResult
    private func reduceAgent(action: AgentReducerAction) -> Bool {
        guard let next = AppLogicBridge.shared.reduceAgent(
            state: agentState,
            cwd: currentDirectory,
            action: action
        ) else {
            return false
        }

        applyAgentState(next)
        return true
    }

    private func applyAgentState(_ next: AgentReducerState) {
        let priorTitle = titleText
        let priorDirectory = currentDirectory
        let priorThreadID = agentState?.threadId

        agentState = next
        currentDirectory = next.cwd
        composer.setBusy(next.busy)
        rebuildFeed(next.rows)

        if next.shouldAutoScroll {
            scrollToBottom()
        }

        if priorTitle != titleText || priorDirectory != currentDirectory || priorThreadID != next.threadId {
            onStateChange?()
        }
    }

    private func rebuildFeed(_ rows: [AgentBridgeRow]) {
        clearFeed()

        for row in rows {
            addFeedRow(makeFeedView(for: row))
        }
    }

    private func makeFeedView(for row: AgentBridgeRow) -> NSView {
        switch row.kind {
        case "message":
            return AgentMessageView(text: row.text ?? "", tone: messageTone(from: row.tone) ?? .assistant)
        case "activity":
            let kind = activityKind(from: row.activity) ?? .trace
            return AgentActivityView(
                kind: kind,
                title: row.title ?? kind.label,
                detail: row.detail,
                text: row.text,
                lines: row.lines ?? []
            )
        default:
            return AgentMessageView(text: row.text ?? "", tone: .assistant)
        }
    }

    private func addFeedRow(_ content: NSView) {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false

        let isTrailingMessage = (content as? AgentMessageView)?.prefersTrailingAlignment == true
        let maxWidthMultiplier = (content as? AgentMessageView)?.maxWidthMultiplier ?? 0.96

        var constraints = [
            content.topAnchor.constraint(equalTo: wrap.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ]

        if content is AgentMessageView {
            constraints.append(content.widthAnchor.constraint(equalTo: wrap.widthAnchor, multiplier: maxWidthMultiplier))
        } else {
            constraints.append(content.widthAnchor.constraint(lessThanOrEqualTo: wrap.widthAnchor, multiplier: maxWidthMultiplier))
        }

        if isTrailingMessage {
            constraints.append(content.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor))
            constraints.append(content.trailingAnchor.constraint(equalTo: wrap.trailingAnchor))
        } else {
            constraints.append(content.leadingAnchor.constraint(equalTo: wrap.leadingAnchor))
            constraints.append(content.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor))
        }

        NSLayoutConstraint.activate(constraints)

        feedStack.addArrangedSubview(wrap)
        wrap.widthAnchor.constraint(equalTo: feedStack.widthAnchor).isActive = true
    }

    private func clearFeed() {
        for view in feedStack.arrangedSubviews {
            feedStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func messageTone(from value: String?) -> AgentMessageTone? {
        switch value {
        case "assistant": return .assistant
        case "user": return .user
        case "status": return .status
        case "error": return .error
        default: return nil
        }
    }

    private func activityKind(from value: String?) -> AgentActivityKind? {
        switch value {
        case "trace": return .trace
        case "edit": return .edit
        default: return nil
        }
    }

    private func scrollToBottom() {
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
        let followsBottom = isNearBottom()
        guard followsBottom != agentState?.shouldAutoScroll else { return }
        _ = reduceAgent(action: AgentReducerAction(
            type: "scrollFollow",
            prompt: nil,
            event: nil,
            completed: nil,
            cancelled: nil,
            stderrText: nil,
            terminationStatus: nil,
            terminationReason: nil,
            snapshot: nil,
            followsBottom: followsBottom
        ))
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
        modelLoadGeneration += 1
        let generation = modelLoadGeneration
        AgentBridge.loadModels(cwd: currentDirectory) { [weak self] options in
            guard let self, generation == self.modelLoadGeneration else { return }
            self.composer.setModels(options)
            self.selectionMenu.setModels(options)
            self.selectionMenu.setSelectedModel(self.composer.model?.model)
        }
    }
}
