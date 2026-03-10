import AppKit
import Foundation
import OsmiumPickerSupport

enum SidebarPickerMode: Equatable {
    case recentChats
    case files(directory: String)
}

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

func sidebarRecentChatEntries(_ threads: [AgentThreadSummary]) -> [SidebarPickerEntry] {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated

    return threads.map { thread in
        let recency = formatter.localizedString(for: Date(timeIntervalSince1970: thread.updatedAt), relativeTo: Date())
        let location = URL(fileURLWithPath: thread.cwd).lastPathComponent.ifEmpty(thread.cwd)
        let secondary = "\(location) · \(recency)"
        let searchText = [thread.title, thread.preview, thread.cwd].joined(separator: "\n").lowercased()

        return SidebarPickerEntry(
            kind: .recentChat,
            primaryText: thread.title,
            secondaryText: secondary,
            searchText: searchText,
            threadId: thread.threadId,
            cwd: thread.cwd
        )
    }
}

final class SidebarPickerCell: NSTableCellView {
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
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)

        primaryLabel.font = cfg.agentFont(size: 13, weight: .medium)
        primaryLabel.lineBreakMode = .byTruncatingMiddle
        primaryLabel.maximumNumberOfLines = 1

        secondaryLabel.font = cfg.agentFont(size: 11)
        secondaryLabel.textColor = cfg.color("theme.overlay_subdued").withAlphaComponent(0.84)
        secondaryLabel.lineBreakMode = .byTruncatingMiddle
        secondaryLabel.maximumNumberOfLines = 1

        stack.addArrangedSubview(primaryLabel)
        stack.addArrangedSubview(secondaryLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(entry: SidebarPickerEntry, selected: Bool) {
        primaryLabel.stringValue = entry.primaryText
        secondaryLabel.stringValue = entry.secondaryText ?? ""
        secondaryLabel.isHidden = entry.secondaryText == nil
        let isInfo = entry.kind == .info
        primaryLabel.textColor = isInfo
            ? cfg.color("theme.overlay_subdued")
            : (selected ? cfg.color("theme.overlay_text") : cfg.color("theme.overlay_text").withAlphaComponent(0.92))
        highlight.alphaValue = selected && !isInfo ? 1 : 0
    }
}
