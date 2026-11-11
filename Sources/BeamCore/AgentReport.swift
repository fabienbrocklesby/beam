/// One change an agent's hook reports for its pane. The `beam` helper sends
/// it to beamd as JSON in a `report` frame, and beamd passes it on to Beam.
public struct AgentReport: Codable, Equatable, Sendable {
    public enum Event: Codable, Equatable, Sendable {
        /// A session started, resumed, or replaced the last one (`/clear`),
        /// and sits at its prompt. Its ID lets a relaunch resume exactly it;
        /// nil when the agent sent none that could be typed safely.
        case started(session: String?)
        case working
        case waiting(message: String)
        case done(message: String?)
        /// The agent has sat at its prompt for a while. Agents report nothing
        /// when the user interrupts a turn, so this is what ends one.
        case idle
        case ended
    }

    /// Paths a hook's payload named, as written: often partial, for Beam
    /// to find on disk (see `TurnFiles` and `FileResolver`).
    public struct Files: Codable, Equatable, Sendable {
        /// The hook's working directory, where relative names start.
        public var directory: String?
        public var names: [String]

        public init(directory: String?, names: [String]) {
            self.directory = directory
            self.names = names
        }
    }

    public let pane: Pane.ID
    public let agent: Agent
    public let event: Event
    /// The files a tool result's input or a finished turn's reply named.
    /// Optional in the JSON, so a helper and a beamd of different versions
    /// still understand each other.
    public let files: Files?

    public init(pane: Pane.ID, agent: Agent, event: Event, files: Files? = nil) {
        self.pane = pane
        self.agent = agent
        self.event = event
        self.files = files
    }
}
