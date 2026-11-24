import Foundation

/// A conversation an agent's CLI keeps on disk: enough to list it and to
/// open it again.
public struct Conversation: Equatable, Sendable {
    public let agent: Agent
    /// What the agent's resume command takes.
    public let session: String
    /// Where it ran. An agent looks a session up by folder, so it resumes
    /// only from here.
    public let folder: String
    public let title: String
    /// When it was last written to.
    public let modified: Date

    public init(agent: Agent, session: String, folder: String, title: String, modified: Date) {
        self.agent = agent
        self.session = session
        self.folder = folder
        self.title = title
        self.modified = modified
    }
}
