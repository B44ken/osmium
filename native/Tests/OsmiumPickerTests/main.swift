import Foundation

import OsmiumPickerSupport

@main
struct OsmiumPickerTests {
    static func main() throws {
        try testFilterPrefersPrefixMatchesBeforeContainsMatches()
        try testDirectoryEntriesIncludeParentAndSortDirectoriesFirst()
        try testTextDetectionDistinguishesUtf8FromBinary()
        try testAgentMarkdownParsesHeadingsInlineFormattingAndCodeBlocks()
        print("OsmiumPickerTests passed")
    }

    private static func testFilterPrefersPrefixMatchesBeforeContainsMatches() throws {
        let entries = [
            SidebarPickerEntry(kind: .file, primaryText: "late.txt", secondaryText: nil, searchText: "late.txt", path: "/tmp/late.txt"),
            SidebarPickerEntry(kind: .file, primaryText: "texfile.txt", secondaryText: nil, searchText: "texfile.txt", path: "/tmp/texfile.txt"),
            SidebarPickerEntry(kind: .file, primaryText: "notes.txt", secondaryText: nil, searchText: "notes.txt", path: "/tmp/notes.txt"),
        ]

        let filtered = sidebarFilterEntries(entries, query: "te")
        try expect(filtered.map { $0.primaryText } == ["texfile.txt", "late.txt", "notes.txt"], "prefix-ranked filter order")
    }

    private static func testDirectoryEntriesIncludeParentAndSortDirectoriesFirst() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Beta"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("alpha"), withIntermediateDirectories: false)
        try "z".write(to: directory.appendingPathComponent("Zoo.txt"), atomically: true, encoding: .utf8)
        try "a".write(to: directory.appendingPathComponent("aardvark.txt"), atomically: true, encoding: .utf8)

        let entries = try sidebarDirectoryEntries(at: directory.path)
        try expect(entries.map { $0.primaryText } == ["../", "alpha/", "Beta/", "aardvark.txt", "Zoo.txt"], "directory ordering")
    }

    private static func testTextDetectionDistinguishesUtf8FromBinary() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let textFile = directory.appendingPathComponent("note.txt")
        let binaryFile = directory.appendingPathComponent("blob.bin")

        try "hello".write(to: textFile, atomically: true, encoding: .utf8)
        try Data([0x00, 0xFF, 0x10, 0x7F]).write(to: binaryFile)

        try expect(sidebarIsLikelyTextFile(at: textFile.path), "utf8 text detection")
        try expect(!sidebarIsLikelyTextFile(at: binaryFile.path), "binary detection")
    }

    private static func testAgentMarkdownParsesHeadingsInlineFormattingAndCodeBlocks() throws {
        let blocks = agentMarkdownBlocks(from: """
        # Title

        Use **bold** and `code`.

        ```swift
        print("hi")
        ```
        """)

        try expect(blocks.count == 3, "markdown block count")
        try expect(blocks[0] == .heading(level: 1, [.text("Title")]), "heading parse")
        try expect(
            blocks[1] == .paragraph([.text("Use "), .bold("bold"), .text(" and "), .code("code"), .text(".")]),
            "inline formatting parse"
        )
        try expect(blocks[2] == .codeBlock("print(\"hi\")"), "code block parse")
    }

    private static func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(domain: "OsmiumPickerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed: \(message)"])
        }
    }
}
