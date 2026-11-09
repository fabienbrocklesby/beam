/// What the agent in a pane is doing, as its own hooks last reported.
public enum AgentState: Equatable, Sendable {
    /// Working on a prompt.
    case working
    /// Blocked on the user, say on a permission prompt; `message` says what for.
    case waiting(message: String)
    /// Finished its turn, so the next move is the user's. `message` is the
    /// start of its reply, or the error it stopped on.
    case done(message: String?)

    /// Whether the user has something to do in the pane.
    public var needsAttention: Bool {
        if case .working = self { false } else { true }
    }

    /// A workspace shows its most urgent pane: one that is blocked beats one
    /// that has finished, which beats one still working.
    var urgency: Int {
        switch self {
        case .working: 0
        case .done: 1
        case .waiting: 2
        }
    }
}
