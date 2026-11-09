import Foundation

/// Where Beam keeps its workspaces between launches: the whole
/// `WorkspaceStore` as versioned JSON. Reads and writes block, so callers
/// keep them off the main thread.
public struct StateFile: Sendable {
    /// A file written by a later Beam whose format this one does not know.
    public struct UnsupportedVersion: Error, Equatable {
        public let version: Int

        public init(version: Int) {
            self.version = version
        }
    }

    private static let version = 1

    private struct Contents: Codable {
        var version: Int
        var store: WorkspaceStore
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Beam/state.json`.
    public static var standard: StateFile {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let folder = support.first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return StateFile(url: folder.appendingPathComponent("Beam/state.json"))
    }

    /// The saved store, or nil when nothing has been saved yet. Throws when
    /// the file cannot be read or decoded.
    public func load() throws -> WorkspaceStore? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        // The version is checked first, so a later format reports that rather
        // than whichever field it changed.
        struct Header: Decodable { var version: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.version == Self.version else { throw UnsupportedVersion(version: header.version) }
        return try JSONDecoder().decode(Contents.self, from: data).store
    }

    /// Replaces the file in one step, so a crash mid-write leaves the last
    /// complete state.
    public func save(_ store: WorkspaceStore) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Contents(version: Self.version, store: store)).write(to: url, options: .atomic)
    }

    /// Renames a file `load` could not read to `state.unreadable.json`,
    /// replacing an older one, so the next save does not destroy it.
    public func moveAside() throws {
        let aside = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".unreadable")
            .appendingPathExtension(url.pathExtension)
        if FileManager.default.fileExists(atPath: aside.path) {
            try FileManager.default.removeItem(at: aside)
        }
        try FileManager.default.moveItem(at: url, to: aside)
    }
}
