import Foundation

/// The panes for one project folder.
public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    /// Stable for the workspace's lifetime and across relaunches. Exported to
    /// its panes' processes as `BEAM_WORKSPACE_ID`.
    public struct ID: Hashable, Codable, Sendable, CustomStringConvertible {
        public let uuid: UUID

        public init(uuid: UUID = UUID()) {
            self.uuid = uuid
        }

        public init(from decoder: any Decoder) throws {
            uuid = try decoder.singleValueContainer().decode(UUID.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(uuid)
        }

        public var description: String { uuid.uuidString }
    }

    /// Tag colours, as in Finder.
    public enum Color: String, Codable, CaseIterable, Sendable {
        case red, orange, yellow, green, blue, purple, gray
    }

    public let id: ID
    /// An absolute, standardized path.
    public let folder: String
    public var name: String
    public var color: Color?
    public var isPinned = false
    public var isArchived = false
    public var tree: SplitTree
    public var focusedPane: Pane.ID?

    /// A workspace with one shell in `folder`.
    public init(folder: String) {
        id = ID()
        self.folder = folder
        name = (folder as NSString).lastPathComponent
        tree = SplitTree()
        reopen()
    }

    /// Starts a shell in the folder if no pane is open.
    mutating func reopen() {
        guard tree.isEmpty else { return }
        let pane = Pane(workingDirectory: folder)
        tree = SplitTree(pane)
        focusedPane = pane.id
    }

    /// Closes every pane.
    mutating func empty() {
        tree = SplitTree()
        focusedPane = nil
    }
}
