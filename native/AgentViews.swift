import AppKit
import Foundation

final class AgentMessageView: NSView {
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private var currentText = ""
    private var currentTone: AgentMessageTone
    private let messageEmphasized: Bool

    var text: String { currentText }

    init(text: String, tone: AgentMessageTone, emphasized: Bool = false) {
        currentTone = tone
        messageEmphasized = emphasized
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setText(text)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        currentText = text
        textLabel.attributedStringValue = attributed(text: text)
    }

    func appendText(_ text: String) {
        currentText += text
        textLabel.attributedStringValue = attributed(text: currentText)
    }

    func setTone(_ tone: AgentMessageTone) {
        currentTone = tone
        textLabel.attributedStringValue = attributed(text: currentText)
    }

    private func attributed(text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 6

        let color: NSColor
        switch currentTone {
        case .assistant:
            color = cfg.color("theme.overlay_text")
        case .user:
            color = cfg.color("theme.overlay_text").withAlphaComponent(0.9)
        case .status:
            color = cfg.color("theme.overlay_subdued")
        case .error:
            color = appColor("ff8b8b")
        }

        return NSAttributedString(string: text, attributes: [
            .font: cfg.agentFont(size: messageEmphasized ? 17 : 15, weight: messageEmphasized ? .semibold : .regular),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }
}

final class AgentActivityView: NSView {
    private let badgeLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let linesLabel = NSTextField(wrappingLabelWithString: "")

    init(kind: AgentActivityKind, title: String, detail: String? = nil, text: String? = nil, lines: [String] = []) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        addSubview(stack)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 10

        badgeLabel.font = cfg.agentFont(size: 12, weight: .semibold)
        badgeLabel.stringValue = kind.label
        badgeLabel.textColor = kind == .edit ? cfg.color("theme.editor_commands") : cfg.color("theme.overlay_subdued")

        titleLabel.font = cfg.agentFont(size: 13, weight: .medium)
        titleLabel.textColor = cfg.color("theme.overlay_text").withAlphaComponent(0.9)
        titleLabel.stringValue = title

        header.addArrangedSubview(badgeLabel)
        header.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(header)

        detailLabel.font = cfg.agentFont(size: 12)
        detailLabel.textColor = cfg.color("theme.overlay_subdued").withAlphaComponent(0.88)
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
        if detail != nil {
            stack.addArrangedSubview(detailLabel)
        }

        textLabel.font = cfg.agentFont(size: 13)
        textLabel.textColor = cfg.color("theme.overlay_text").withAlphaComponent(0.82)
        textLabel.stringValue = text ?? ""
        textLabel.isHidden = text == nil
        if text != nil {
            stack.addArrangedSubview(textLabel)
        }

        linesLabel.font = cfg.mono(12)
        linesLabel.textColor = cfg.color("theme.overlay_subdued").withAlphaComponent(0.84)
        linesLabel.stringValue = lines.joined(separator: "\n")
        linesLabel.isHidden = lines.isEmpty
        if !lines.isEmpty {
            stack.addArrangedSubview(linesLabel)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class AgentReasoningRowView: NSView {
    let preset: AgentReasoningPreset
    var onSelect: ((AgentReasoningPreset) -> Void)?

    private let keyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(preset: AgentReasoningPreset) {
        self.preset = preset
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        if #available(macOS 13.0, *) {
            layer?.cornerCurve = .continuous
        }

        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.font = cfg.mono(13, .semibold)
        keyLabel.stringValue = preset.key

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = cfg.agentFont(size: 13, weight: .medium)
        titleLabel.stringValue = preset.title

        addSubview(keyLabel)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        setSelected(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onSelect?(preset)
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (selected ? NSColor.white.withAlphaComponent(0.09) : .clear).cgColor
        keyLabel.textColor = selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_subdued")
        titleLabel.textColor = selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_subdued").withAlphaComponent(0.88)
    }
}

final class AgentModelRowView: NSView {
    let option: AgentModelOption
    var onSelect: ((AgentModelOption) -> Void)?

    private let keyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(option: AgentModelOption) {
        self.option = option
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        if #available(macOS 13.0, *) {
            layer?.cornerCurve = .continuous
        }

        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.font = cfg.mono(13, .semibold)
        keyLabel.stringValue = option.key

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = cfg.agentFont(size: 13, weight: .medium)
        titleLabel.stringValue = option.displayName
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(keyLabel)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        setSelected(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onSelect?(option)
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = (selected ? NSColor.white.withAlphaComponent(0.09) : .clear).cgColor
        keyLabel.textColor = selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_subdued")
        titleLabel.textColor = selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_subdued").withAlphaComponent(0.92)
    }
}

final class AgentSelectionMenuView: NSView {
    var onSelectReasoning: ((AgentReasoningPreset) -> Void)?
    var onSelectModel: ((AgentModelOption) -> Void)?

    private var rows: [AgentReasoningPreset: AgentReasoningRowView] = [:]
    private let modelSection = NSStackView()
    private let reasoningSection = NSStackView()
    private let modelsHeader = NSTextField(labelWithString: "model")
    private let reasoningHeader = NSTextField(labelWithString: "reasoning")
    private let modelsEmptyLabel = NSTextField(labelWithString: "loading...")
    private var modelRows: [String: AgentModelRowView] = [:]
    private let reasoningBox = NSVisualEffectView()
    private let modelBox = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
        isHidden = true

        let columns = NSStackView()
        columns.translatesAutoresizingMaskIntoConstraints = false
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 16
        addSubview(columns)

        reasoningSection.orientation = .vertical
        reasoningSection.alignment = .leading
        reasoningSection.spacing = 6

        reasoningHeader.font = cfg.agentFont(size: 12, weight: .semibold)
        reasoningHeader.textColor = cfg.color("theme.overlay_text")
        reasoningSection.addArrangedSubview(reasoningHeader)

        for preset in AgentReasoningPreset.allCases {
            let row = AgentReasoningRowView(preset: preset)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 132).isActive = true
            row.onSelect = { [weak self] selection in
                self?.onSelectReasoning?(selection)
            }
            rows[preset] = row
            reasoningSection.addArrangedSubview(row)
        }

        modelSection.orientation = .vertical
        modelSection.alignment = .leading
        modelSection.spacing = 6

        modelsHeader.font = cfg.agentFont(size: 12, weight: .semibold)
        modelsHeader.textColor = cfg.color("theme.overlay_text")

        modelsEmptyLabel.font = cfg.agentFont(size: 12, weight: .medium)
        modelsEmptyLabel.textColor = cfg.color("theme.overlay_subdued").withAlphaComponent(0.72)

        modelSection.addArrangedSubview(modelsHeader)
        modelSection.addArrangedSubview(modelsEmptyLabel)

        configureBox(reasoningBox, content: reasoningSection)
        configureBox(modelBox, content: modelSection)

        columns.addArrangedSubview(reasoningBox)
        columns.addArrangedSubview(modelBox)

        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: trailingAnchor),
            columns.topAnchor.constraint(equalTo: topAnchor),
            columns.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSelectedReasoning(_ preset: AgentReasoningPreset) {
        for (candidate, row) in rows {
            row.setSelected(candidate == preset)
        }
    }

    func setModels(_ options: [AgentModelOption]) {
        for row in modelRows.values {
            modelSection.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        modelRows.removeAll()

        if options.isEmpty {
            modelsEmptyLabel.stringValue = "loading..."
            if modelsEmptyLabel.superview == nil {
                modelSection.addArrangedSubview(modelsEmptyLabel)
            }
            return
        }

        if modelsEmptyLabel.superview != nil {
            modelSection.removeArrangedSubview(modelsEmptyLabel)
            modelsEmptyLabel.removeFromSuperview()
        }

        for option in options {
            let row = AgentModelRowView(option: option)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 220).isActive = true
            row.onSelect = { [weak self] selection in
                self?.onSelectModel?(selection)
            }
            modelRows[option.model] = row
            modelSection.addArrangedSubview(row)
        }
    }

    func setSelectedModel(_ model: String?) {
        for (candidate, row) in modelRows {
            row.setSelected(candidate == model)
        }
    }

    private func configureBox(_ box: NSVisualEffectView, content: NSStackView) {
        box.translatesAutoresizingMaskIntoConstraints = false
        box.glass(radius: 14, border: cfg.color("theme.panel_border"), bg: NSColor.black.withAlphaComponent(0.18))
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
    }
}

final class AgentComposerTextView: NSTextView {
    var onShortcut: ((String, NSEvent.ModifierFlags, UInt16) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if onShortcut?(key, modifiers, event.keyCode) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class AgentComposerView: NSVisualEffectView, NSTextViewDelegate {
    let textView = AgentComposerTextView()
    var onSubmit: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onPickerVisibilityChanged: ((Bool) -> Void)?
    var onReasoningChanged: ((AgentReasoningPreset) -> Void)?
    var onModelChanged: ((AgentModelOption?) -> Void)?

    private let placeholder = NSTextField(labelWithString: "")
    private var pickerVisible = false
    private var selectedReasoning: AgentReasoningPreset = .xhigh
    private var models: [AgentModelOption] = []
    private var selectedModelOption: AgentModelOption?
    private var busy = false

    var reasoning: AgentReasoningPreset { selectedReasoning }
    var model: AgentModelOption? { selectedModelOption }
    var isPickerVisible: Bool { pickerVisible }

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass(radius: 16, border: cfg.color("theme.panel_border"), bg: NSColor.white.withAlphaComponent(0.03))

        let editorScroll = NSScrollView()
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = false
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.scrollerStyle = .overlay
        addSubview(editorScroll)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.drawsBackground = false
        textView.font = cfg.agentFont(size: 15)
        textView.textColor = cfg.color("theme.overlay_text")
        textView.insertionPointColor = cfg.color("theme.overlay_text")
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.onShortcut = { [weak self] key, modifiers, keyCode in
            self?.handleShortcut(key: key, modifiers: modifiers, keyCode: keyCode) ?? false
        }
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        editorScroll.documentView = textView

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = cfg.agentFont(size: 15)
        placeholder.textColor = cfg.color("theme.overlay_subdued").withAlphaComponent(0.55)
        addSubview(placeholder)

        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            editorScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            editorScroll.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            editorScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            placeholder.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor, constant: 4),
            placeholder.topAnchor.constraint(equalTo: editorScroll.topAnchor, constant: 6),
        ])

        updatePlaceholder()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setBusy(_ busy: Bool) {
        self.busy = busy
        textView.isEditable = !busy
        if busy {
            dismissPicker()
        }
        updatePlaceholder()
    }

    func clear() {
        textView.string = ""
        updatePlaceholder()
    }

    func textDidChange(_ notification: Notification) {
        updatePlaceholder()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        false
    }

    private func handleShortcut(key: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        if pickerVisible {
            if keyCode == 53 {
                dismissPicker()
                return true
            }
            if modifiers.isEmpty || modifiers == .command {
                if let preset = AgentReasoningPreset.fromSelectionKey(key) {
                    setReasoning(preset)
                    dismissPicker()
                    return true
                }
                if let index = Int(key), let option = models.first(where: { $0.index == index }) {
                    selectModel(option)
                    dismissPicker()
                    return true
                }
            }
        }

        if modifiers == .command && (keyCode == 36 || keyCode == 76) {
            performPrimaryAction()
            return true
        }

        if modifiers == .command && key == "m" {
            togglePicker()
            return true
        }

        return false
    }

    private func submitDraft() {
        let prompt = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !prompt.isEmpty else { return }
        dismissPicker()
        onSubmit?(prompt)
    }

    private func performPrimaryAction() {
        if busy { onStop?() }
        else { submitDraft() }
    }

    private func updatePlaceholder() {
        placeholder.stringValue = busy ? "working... cmd enter to stop" : "ready"
        placeholder.isHidden = !textView.string.isEmpty
    }

    @objc private func togglePicker() {
        setPickerVisible(!pickerVisible)
    }

    func dismissPicker() {
        setPickerVisible(false)
    }

    func selectReasoning(_ reasoning: AgentReasoningPreset) {
        setReasoning(reasoning)
    }

    func setModels(_ models: [AgentModelOption]) {
        self.models = models
        if let selectedModelOption, models.contains(where: { $0.model == selectedModelOption.model }) {
            return
        }
        if let next = models.first(where: \.isDefault) ?? models.first {
            selectModel(next)
        } else {
            selectedModelOption = nil
            onModelChanged?(nil)
        }
    }

    func selectModel(_ model: AgentModelOption) {
        guard selectedModelOption?.model != model.model else { return }
        selectedModelOption = model
        onModelChanged?(model)
    }

    private func setReasoning(_ reasoning: AgentReasoningPreset) {
        guard selectedReasoning != reasoning else { return }
        selectedReasoning = reasoning
        onReasoningChanged?(reasoning)
    }

    private func setPickerVisible(_ visible: Bool) {
        guard pickerVisible != visible else { return }
        pickerVisible = visible
        onPickerVisibilityChanged?(visible)
    }
}
