/// What beamd tells Beam on its control connection, one per `control` frame.
public enum ControlEvent: Codable, Equatable, Sendable {
    /// A session beamd runs.
    public struct Session: Codable, Equatable, Sendable {
        public var pane: Pane.ID
        /// What its agent reported that still holds, to apply in order (see
        /// `AgentReports`).
        public var reports: [AgentReport]

        public init(pane: Pane.ID, reports: [AgentReport]) {
            self.pane = pane
            self.reports = reports
        }
    }

    /// The answer to `ControlRequest.list`.
    case sessions([Session])
    /// A report an agent's hook just sent, passed on as it arrives.
    case report(AgentReport)
}
