import Foundation

public enum AgentMarkdownInline: Equatable {
    case text(String)
    case bold(String)
    case code(String)
}

public enum AgentMarkdownBlock: Equatable {
    case paragraph([AgentMarkdownInline])
    case heading(level: Int, [AgentMarkdownInline])
    case codeBlock(String)
}

public func agentMarkdownBlocks(from text: String) -> [AgentMarkdownBlock] {
    guard !text.isEmpty else { return [] }

    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [AgentMarkdownBlock] = []
    var paragraphLines: [String] = []
    var codeLines: [String] = []
    var inCodeBlock = false

    func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        let combined = paragraphLines.joined(separator: "\n")
        blocks.append(.paragraph(agentMarkdownInlines(from: combined)))
        paragraphLines.removeAll()
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if inCodeBlock {
            if trimmed.hasPrefix("```") {
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                codeLines.removeAll()
                inCodeBlock = false
            } else {
                codeLines.append(line)
            }
            continue
        }

        if trimmed.hasPrefix("```") {
            flushParagraph()
            inCodeBlock = true
            continue
        }

        if trimmed.isEmpty {
            flushParagraph()
            continue
        }

        if let heading = agentMarkdownHeading(from: line) {
            flushParagraph()
            blocks.append(.heading(level: heading.level, agentMarkdownInlines(from: heading.text)))
            continue
        }

        paragraphLines.append(line)
    }

    flushParagraph()
    if inCodeBlock {
        blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
    }
    return blocks
}

private func agentMarkdownHeading(from line: String) -> (level: Int, text: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.first == "#" else { return nil }

    var hashes = 0
    var index = trimmed.startIndex
    while index < trimmed.endIndex, trimmed[index] == "#", hashes < 6 {
        hashes += 1
        index = trimmed.index(after: index)
    }

    guard hashes > 0, index < trimmed.endIndex, trimmed[index] == " " else { return nil }
    let textStart = trimmed.index(after: index)
    let text = String(trimmed[textStart...])
    guard !text.isEmpty else { return nil }
    return (min(hashes, 3), text)
}

private func agentMarkdownInlines(from text: String) -> [AgentMarkdownInline] {
    guard !text.isEmpty else { return [] }

    var inlines: [AgentMarkdownInline] = []
    var buffer = ""
    var index = text.startIndex

    func flushBuffer() {
        guard !buffer.isEmpty else { return }
        inlines.append(.text(buffer))
        buffer.removeAll(keepingCapacity: true)
    }

    while index < text.endIndex {
        if text[index...].hasPrefix("**") {
            let start = text.index(index, offsetBy: 2)
            if let close = text[start...].range(of: "**") {
                let content = String(text[start..<close.lowerBound])
                if !content.isEmpty {
                    flushBuffer()
                    inlines.append(.bold(content))
                    index = close.upperBound
                    continue
                }
            }
        }

        if text[index] == "`" {
            let start = text.index(after: index)
            if let close = text[start...].firstIndex(of: "`") {
                let content = String(text[start..<close])
                if !content.isEmpty {
                    flushBuffer()
                    inlines.append(.code(content))
                    index = text.index(after: close)
                    continue
                }
            }
        }

        buffer.append(text[index])
        index = text.index(after: index)
    }

    flushBuffer()
    return inlines
}
