import Foundation

public enum SidebarPickerEntryKind: Equatable {
    case info
    case recentChat
    case parentDirectory
    case directory
    case file
}

public struct SidebarPickerEntry: Equatable {
    public let kind: SidebarPickerEntryKind
    public let primaryText: String
    public let secondaryText: String?
    public let searchText: String
    public let path: String?
    public let threadId: String?
    public let cwd: String?

    public var isActivatable: Bool { kind != .info }

    public init(
        kind: SidebarPickerEntryKind,
        primaryText: String,
        secondaryText: String?,
        searchText: String,
        path: String? = nil,
        threadId: String? = nil,
        cwd: String? = nil
    ) {
        self.kind = kind
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.searchText = searchText
        self.path = path
        self.threadId = threadId
        self.cwd = cwd
    }
}

public func sidebarInfoEntry(_ text: String) -> SidebarPickerEntry {
    SidebarPickerEntry(
        kind: .info,
        primaryText: text,
        secondaryText: nil,
        searchText: text.lowercased()
    )
}

public func sidebarFilterEntries(_ entries: [SidebarPickerEntry], query: String) -> [SidebarPickerEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return entries }

    return entries
        .enumerated()
        .compactMap { offset, entry -> (rank: Int, offset: Int, entry: SidebarPickerEntry)? in
            guard entry.isActivatable else { return nil }
            let haystack = entry.searchText.lowercased()
            if haystack.hasPrefix(trimmed) || entry.primaryText.lowercased().hasPrefix(trimmed) {
                return (0, offset, entry)
            }
            if haystack.contains(trimmed) {
                return (1, offset, entry)
            }
            return nil
        }
        .sorted { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.offset < rhs.offset : lhs.rank < rhs.rank
        }
        .map(\.entry)
}

public func sidebarDirectoryEntries(at directory: String) throws -> [SidebarPickerEntry] {
    let fileManager = FileManager.default
    let url = URL(fileURLWithPath: directory)
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey]
    let urls = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [])

    let items = try urls.map { url -> (isDirectory: Bool, name: String, entry: SidebarPickerEntry) in
        let values = try url.resourceValues(forKeys: keys)
        let isDirectory = values.isDirectory ?? false
        let name = values.name ?? url.lastPathComponent
        let primary = isDirectory ? "\(name)/" : name
        return (
            isDirectory,
            name,
            SidebarPickerEntry(
                kind: isDirectory ? .directory : .file,
                primaryText: primary,
                secondaryText: nil,
                searchText: name.lowercased(),
                path: url.path
            )
        )
    }
    .sorted { lhs, rhs in
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        let left = lhs.name.localizedLowercase
        let right = rhs.name.localizedLowercase
        if left == right {
            return lhs.name < rhs.name
        }
        return left < right
    }
    .map(\.entry)

    guard directory != "/" else { return items }

    let parent = url.deletingLastPathComponent().path.isEmpty ? "/" : url.deletingLastPathComponent().path
    return [
        SidebarPickerEntry(
            kind: .parentDirectory,
            primaryText: "../",
            secondaryText: nil,
            searchText: "..",
            path: parent
        )
    ] + items
}

public func sidebarIsLikelyTextFile(at path: String, sampleSize: Int = 4096) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }

    let data = handle.readData(ofLength: sampleSize)
    if data.isEmpty { return true }
    if data.contains(0) { return false }
    return String(data: data, encoding: .utf8) != nil
}
