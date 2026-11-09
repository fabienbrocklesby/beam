/// How a relaunched Beam meets the sessions beamd kept running while it was
/// not.
public struct SessionRestore: Equatable, Sendable {
    /// Panes whose session beamd still runs.
    public let live: Set<Pane.ID>

    public init(live: some Sequence<Pane.ID>) {
        self.live = Set(live)
    }

    /// What `pane` types into its terminal as it starts. A live session is
    /// attached as it is, whatever runs in it, so it gets nothing. Any other
    /// pane starts a fresh session and types its command, which
    /// `WorkspaceStore.prepareForLaunch` made the agent's resume form.
    public func initialCommand(for pane: Pane) -> String? {
        live.contains(pane.id) ? nil : pane.command
    }

    /// Live sessions no pane in `store` will attach to, which would otherwise
    /// run on unseen. Only a store read from a state file says which panes
    /// exist; without one, nothing counts as an orphan.
    public func orphans(in store: WorkspaceStore, stateLoaded: Bool) -> [Pane.ID] {
        guard stateLoaded else { return [] }
        let panes = Set(store.workspaces.flatMap { $0.tree.panes.map(\.id) })
        return live.subtracting(panes).sorted { $0.description < $1.description }
    }
}
