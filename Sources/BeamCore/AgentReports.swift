/// What each session's agent has reported that still holds, so a Beam that
/// connects later learns what happened while it was not running.
///
/// Only two reports per pane are kept: the latest `started`, which names the
/// conversation a relaunch after a reboot resumes, and the report of the
/// state still in effect, an `ended` once the session is over. Applied in
/// order to a fresh `AgentActivity`, they leave it where every report so far
/// would have.
public struct AgentReports: Equatable, Sendable {
    private var started: [Pane.ID: AgentReport] = [:]
    private var states: [Pane.ID: AgentReport] = [:]

    public init() {}

    public mutating func record(_ report: AgentReport) {
        let pane = report.pane
        switch report.event {
        case .started:
            started[pane] = report
            states[pane] = nil
        case .working, .waiting, .done, .ended:
            states[pane] = report
        case .idle:
            // As in AgentActivity: it only ends a turn still marked working.
            if states[pane]?.event == .working { states[pane] = nil }
        }
    }

    /// The kept reports for `pane`, oldest first.
    public func latest(for pane: Pane.ID) -> [AgentReport] {
        [started[pane], states[pane]].compactMap(\.self)
    }

    /// Drops what `pane` reported: its session has ended.
    public mutating func forget(_ pane: Pane.ID) {
        started[pane] = nil
        states[pane] = nil
    }
}
