import Foundation

/// One terminal in a workspace: what Beam needs to start it again.
public struct Pane: Codable, Equatable, Identifiable, Sendable {
    /// Stable for the pane's lifetime and across relaunches. Exported to the
    /// pane's processes as `BEAM_PANE_ID`.
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

    public let id: ID
    /// Where the shell starts, kept current as the shell reports `cd`.
    public var workingDirectory: String?
    /// Typed into the pane's shell as it starts, so it runs with everything
    /// the user's rc files set up. Cleared once it finishes, so a relaunch
    /// only starts again what was still running.
    public var command: String?
    /// The session `command`'s agent reported, so a relaunch resumes that
    /// conversation rather than the folder's most recent one.
    public var agentSession: String?

    public init(id: ID = ID(), workingDirectory: String? = nil, command: String? = nil, agentSession: String? = nil) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.command = command
        self.agentSession = agentSession
    }
}
