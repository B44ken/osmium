import AppKit
import Foundation
import OsmiumPickerSupport

final class SidebarTableView: NSTableView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class SidebarRowCell: NSTableCellView {
    private let highlight = NSVisualEffectView()
    private let stack = NSStackView()
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        highlight.glass(.selection, radius: 10)
        highlight.alphaValue = 0
        addSubview(highlight)
        highlight.pin(to: self, insets: NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)

        primaryLabel.font = .systemFont(ofSize: 14, weight: .medium)
        primaryLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.maximumNumberOfLines = 1
        primaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        secondaryLabel.font = .systemFont(ofSize: 12, weight: .regular)
        secondaryLabel.textColor = cfg.color("theme.overlay_subdued").withAlphaComponent(0.84)
        secondaryLabel.lineBreakMode = .byTruncatingTail
        secondaryLabel.maximumNumberOfLines = 1
        secondaryLabel.alignment = .right
        secondaryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.addArrangedSubview(primaryLabel)
        stack.addArrangedSubview(secondaryLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configureTab(text: String, selected: Bool) {
        primaryLabel.stringValue = text
        primaryLabel.textColor = selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_subdued")
        secondaryLabel.stringValue = ""
        secondaryLabel.isHidden = true
        highlight.alphaValue = selected ? 1 : 0
    }

    func configure(primaryText: String, secondaryText: String?, isInfo: Bool, selected: Bool) {
        self.primaryLabel.stringValue = primaryText
        self.secondaryLabel.stringValue = secondaryText ?? ""
        self.secondaryLabel.isHidden = secondaryText == nil
        primaryLabel.textColor = isInfo
            ? cfg.color("theme.overlay_subdued")
            : (selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_text").withAlphaComponent(0.92))
        highlight.alphaValue = selected && !isInfo ? 1 : 0
    }
}
