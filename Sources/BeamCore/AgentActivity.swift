/// The agent state of every pane whose agent has reported one. Not saved:
/// agents report afresh when they start again.
public struct AgentActivity: Equatable, Sendable {
    private var states: [Pane.ID: AgentState] = [:]

    public init() {}

    public subscript(pane: Pane.ID) -> AgentState? { states[pane] }

    /// Applies what `pane`'s agent reported, and says whether the pane now
    /// needs the user when it did not before: the moment to tell them.
    @discardableResult
    public mutating func apply(_ event: AgentReport.Event, to pane: Pane.ID) -> Bool {
        let neededAttention = states[pane]?.needsAttention == true
        switch event {
        case .started, .ended:
            states[pane] = nil
        case .working:
            states[pane] = .working
        case .waiting(let message):
            states[pane] = .waiting(message: message)
        case .done(let message):
            states[pane] = .done(message: message)
        case .idle:
            if states[pane] == .working { states[pane] = nil }
        }
        return !neededAttention && states[pane]?.needsAttention == true
    }

    /// The user has looked at `pane`, so a finished turn no longer needs
    /// them. A blocked agent still does until it moves on.
    public mutating func acknowledge(_ pane: Pane.ID) {
        if case .done = states[pane] { states[pane] = nil }
    }

    /// Drops what `pane` reported: its agent has exited, or the pane is gone.
    public mutating func forget(_ pane: Pane.ID) {
        states[pane] = nil
    }

    /// The most urgent state among `panes`, the first of them on a tie.
    public func summary(of panes: [Pane.ID]) -> AgentState? {
        panes.compactMap { states[$0] }.reduce(nil) { best, state in
            guard let best, best.urgency >= state.urgency else { return state }
            return best
        }
    }

    /// The first pane after `current` in `order` whose agent needs the user,
    /// wrapping round to `current` itself last.
    public func next(after current: Pane.ID?, in order: [Pane.ID]) -> Pane.ID? {
        let start = current.flatMap { order.firstIndex(of: $0).map { $0 + 1 } } ?? 0
        let rotated = order[start...] + order[..<start]
        return rotated.first { states[$0]?.needsAttention == true }
    }
}
