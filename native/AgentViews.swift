import AppKit
import Foundation
import OsmiumPickerSupport

final class AgentMessageView: NSView {
    private let contentView = NSView()
    private let bubbleView = NSVisualEffectView()
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private var currentText = ""
    private var currentTone: AgentMessageTone
    private let messageEmphasized: Bool
    private var textLeadingConstraint: NSLayoutConstraint?
    private var textTrailingConstraint: NSLayoutConstraint?
    private var textTopConstraint: NSLayoutConstraint?
    private var textBottomConstraint: NSLayoutConstraint?

    var text: String { currentText }
    var prefersTrailingAlignment: Bool { currentTone == .user }
    var maxWidthMultiplier: CGFloat { currentTone == .user ? 0.84 : 0.96 }

    init(text: String, tone: AgentMessageTone, emphasized: Bool = false) {
        currentTone = tone
        messageEmphasized = emphasized
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.glass(
            .selection,
            radius: 12,
            bg: NSColor.white.withAlphaComponent(0.04)
        )
        contentView.addSubview(bubbleView)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.allowsDefaultTighteningForTruncation = false
        contentView.addSubview(textLabel)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        textLeadingConstraint = textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        textTrailingConstraint = textLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        textTopConstraint = textLabel.topAnchor.constraint(equalTo: contentView.topAnchor)
        textBottomConstraint = textLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        NSLayoutConstraint.activate([
            textLeadingConstraint!,
            textTrailingConstraint!,
            textTopConstraint!,
            textBottomConstraint!,
        ])

        applyToneStyling()
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
        applyToneStyling()
        textLabel.attributedStringValue = attributed(text: currentText)
    }

    private func applyToneStyling() {
        let showsBubble = currentTone == .user
        bubbleView.alphaValue = showsBubble ? 1 : 0
        bubbleView.layer?.borderWidth = 0
        bubbleView.layer?.backgroundColor = showsBubble ? NSColor.white.withAlphaComponent(0.04).cgColor : NSColor.clear.cgColor
        textLeadingConstraint?.constant = showsBubble ? 12 : 0
        textTrailingConstraint?.constant = showsBubble ? -12 : 0
        textTopConstraint?.constant = showsBubble ? 9 : 0
        textBottomConstraint?.constant = showsBubble ? -9 : 0
    }

    private func attributed(text: String) -> NSAttributedString {
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

        let baseSize = messageEmphasized ? CGFloat(17) : CGFloat(15)
        if currentTone == .user {
            return NSAttributedString(string: text, attributes: baseAttributes(size: baseSize, weight: messageEmphasized ? .semibold : .regular, color: color))
        }

        let blocks = agentMarkdownBlocks(from: text)
        guard !blocks.isEmpty else {
            return NSAttributedString(string: text, attributes: baseAttributes(size: baseSize, weight: messageEmphasized ? .semibold : .regular, color: color))
        }

        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n\n", attributes: baseAttributes(size: baseSize, color: color)))
            }

            switch block {
            case .paragraph(let inlines):
                output.append(render(inlines: inlines, size: baseSize, color: color, weight: messageEmphasized ? .semibold : .regular))
            case .heading(let level, let inlines):
                output.append(render(inlines: inlines, size: headingSize(for: level, baseSize: baseSize), color: color, weight: .semibold, lineSpacing: 4))
            case .codeBlock(let code):
                output.append(renderCodeBlock(code, baseSize: baseSize, color: color))
            }
        }

        return output
    }

    private func baseAttributes(
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor,
        lineSpacing: CGFloat = 5
    ) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 0
        return [
            .font: cfg.agentFont(size: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
    }

    private func render(
        inlines: [AgentMarkdownInline],
        size: CGFloat,
        color: NSColor,
        weight: NSFont.Weight,
        lineSpacing: CGFloat = 5
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for inline in inlines {
            switch inline {
            case .text(let value):
                output.append(NSAttributedString(string: value, attributes: baseAttributes(size: size, weight: weight, color: color, lineSpacing: lineSpacing)))
            case .bold(let value):
                output.append(NSAttributedString(string: value, attributes: baseAttributes(size: size, weight: .semibold, color: color, lineSpacing: lineSpacing)))
            case .code(let value):
                let style = NSMutableParagraphStyle()
                style.lineSpacing = lineSpacing
                style.paragraphSpacing = 0
                output.append(NSAttributedString(string: value, attributes: [
                    .font: cfg.font(size: max(size - 1, 13), weight: .regular),
                    .foregroundColor: color.withAlphaComponent(0.96),
                    .backgroundColor: NSColor.white.withAlphaComponent(0.08),
                    .paragraphStyle: style,
                ]))
            }
        }
        return output
    }

    private func renderCodeBlock(_ code: String, baseSize: CGFloat, color: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 0
        style.headIndent = 10
        style.firstLineHeadIndent = 10

        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map { "  \($0)" }
        let rendered = lines.joined(separator: "\n")
        return NSAttributedString(string: rendered, attributes: [
            .font: cfg.font(size: max(baseSize - 1, 13), weight: .regular),
            .foregroundColor: color.withAlphaComponent(0.95),
            .backgroundColor: NSColor.white.withAlphaComponent(0.06),
            .paragraphStyle: style,
        ])
    }

    private func headingSize(for level: Int, baseSize: CGFloat) -> CGFloat {
        switch level {
        case 1:
            return baseSize * 1.5
        case 2:
            return baseSize * 1.32
        default:
            return baseSize * 1.16
        }
    }
}

final class AgentActivityView: NSView {
    private let lineLabel = NSTextField(labelWithString: "")

    init(kind: AgentActivityKind, badge: String? = nil, title: String, detail: String? = nil, text: String? = nil, lines: [String] = []) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        lineLabel.translatesAutoresizingMaskIntoConstraints = false
        lineLabel.maximumNumberOfLines = 1
        lineLabel.lineBreakMode = .byTruncatingTail
        lineLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lineLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lineLabel.attributedStringValue = activityLine(kind: kind, badge: badge, title: title, detail: detail, text: text, lines: lines)
        addSubview(lineLabel)

        NSLayoutConstraint.activate([
            lineLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            lineLabel.topAnchor.constraint(equalTo: topAnchor),
            lineLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let size = lineLabel.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
    }

    private func activityLine(
        kind: AgentActivityKind,
        badge: String?,
        title: String,
        detail: String?,
        text: String?,
        lines: [String]
    ) -> NSAttributedString {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (trimmedText?.isEmpty == false ? trimmedText : nil)
            ?? lines.first
            ?? detailRemainder(detail)
            ?? title
        let status = activityStatus(detail)
        let lead = badge ?? activityDuration(detail)
        let tagColor = activityTagColor(status)

        let output = NSMutableAttributedString()
        if kind == .edit {
            output.append(tag("[\(title)]", color: tagColor))
            if let lead {
                output.append(space(color: tagColor))
                output.append(tag("[\(lead)]", color: tagColor))
            }
            output.append(space(color: cfg.color("theme.overlay_subdued").withAlphaComponent(0.84)))
        } else {
            if let lead {
                output.append(tag("[\(lead)]", color: tagColor))
                output.append(space(color: tagColor))
            }
            output.append(tag("[\(title)]", color: tagColor))
            output.append(space(color: cfg.color("theme.overlay_subdued").withAlphaComponent(0.84)))
        }
        output.append(NSAttributedString(string: body, attributes: [
            .font: cfg.mono(12),
            .foregroundColor: cfg.color("theme.overlay_text").withAlphaComponent(0.84),
        ]))
        return output
    }

    private func tag(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: cfg.mono(12, .semibold),
            .foregroundColor: color,
        ])
    }

    private func space(color: NSColor) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [
            .font: cfg.mono(12),
            .foregroundColor: color,
        ])
    }

    private func activityStatus(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let parts = detail.split(separator: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for part in parts {
            if ["running", "pending", "in progress"].contains(part) { return "pending" }
            if ["failed", "error"].contains(part) { return "failed" }
        }
        return nil
    }

    private func activityDuration(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let parts = detail.split(separator: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.first(where: {
            $0.hasSuffix("ms")
            || $0.hasSuffix("s")
            || $0.hasSuffix("m")
        })
    }

    private func detailRemainder(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let parts = detail.split(separator: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let kept = parts.filter {
            !$0.isEmpty
            && $0 != activityDuration(detail)
            && activityStatus($0) == nil
        }
        let text = kept.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private func activityStatus(_ value: String) -> String? {
        let lowered = value.lowercased()
        if ["running", "pending", "in progress"].contains(lowered) { return "pending" }
        if ["failed", "error"].contains(lowered) { return "failed" }
        return nil
    }

    private func activityTagColor(_ status: String?) -> NSColor {
        switch status {
        case "pending":
            return cfg.color("theme.overlay_subdued").withAlphaComponent(0.72)
        case "failed":
            return appColor("ff8b8b")
        default:
            return cfg.color("theme.overlay_text").withAlphaComponent(0.88)
        }
    }
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
    private let editorScroll = NSScrollView()
    private var pickerVisible = false
    private var selectedReasoning: AgentReasoningPreset = cfg.agentDefaultReasoning
    private var models: [AgentModelOption] = []
    private var selectedModelOption: AgentModelOption?
    private var busy = false

    var reasoning: AgentReasoningPreset { selectedReasoning }
    var model: AgentModelOption? { selectedModelOption }
    var isPickerVisible: Bool { pickerVisible }

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass(radius: 16, border: cfg.color("theme.panel_border"), bg: NSColor.white.withAlphaComponent(0.03))

        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = false
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
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
        textView.textContainer?.containerSize = NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
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

    override func layout() {
        super.layout()
        let width = max(editorScroll.contentSize.width, 1)
        if textView.frame.width != width {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
        textView.minSize = NSSize(width: width, height: 0)
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }

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
        if let configured = cfg.agentDefaultModel,
           let next = models.first(where: {
               $0.model.caseInsensitiveCompare(configured) == .orderedSame
               || $0.displayName.caseInsensitiveCompare(configured) == .orderedSame
           })
        {
            selectModel(next)
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
