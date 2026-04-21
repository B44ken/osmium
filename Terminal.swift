import AppKit
import SwiftTerm

final class Term: NSView {
    private let term: LocalProcessTerminalView
    private let inset: CGFloat

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(term) ?? false
    }

    override func layout() {
        super.layout()
        term.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    init(pad: CGFloat = 12, inset: CGFloat = 6) {
        self.inset = inset
        term = LocalProcessTerminalView(frame: .zero)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = pad
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        term.font = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
        MainActor.assumeIsolated { term.getTerminal().setCursorStyle(.steadyBlock) }
        term.caretColor = .white
        term.nativeForegroundColor = .white
        term.nativeBackgroundColor = .black
        term.startProcess(executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        addSubview(term)
    }
    required init?(coder: NSCoder) { fatalError() }
}
