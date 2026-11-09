/// What Beam asks of beamd on its control connection, one per `control`
/// frame.
public enum ControlRequest: Codable, Equatable, Sendable {
    /// Every session beamd runs, answered with `ControlEvent.sessions`.
    case list
    /// Ends the pane's session as closing a terminal ends its shell: the
    /// shell is hung up, and the pane's attachment closes once it exits.
    case end(pane: Pane.ID)
    /// Ends every session, for Quit and End Sessions.
    case endAll
}
