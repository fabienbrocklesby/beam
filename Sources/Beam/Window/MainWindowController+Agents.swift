import AppKit
import BeamCore

// What agents report through their hooks, and what the user has seen of it.
extension MainWindowController {
    /// Applies a report from the agent in `report.pane`. `notifies` is
    /// false for what beamd kept while Beam was not running, which the
    /// sidebar shows instead.
    func handle(_ report: AgentReport, notifies: Bool = true) {
        // The pane may have closed since its agent's hook ran.
        guard store.workspaceID(containing: report.pane) != nil else { return }
        if case .started(let session) = report.event {
            update(movesKeyboardFocus: false) {
                $0.updatePane(report.pane) { pane in
                    // Only an agent Beam started is resumed, by its command.
                    if pane.command != nil { pane.agentSession = session }
                }
            }
        }
        let needsUser = activity.apply(report.event, from: report.agent, to: report.pane)
        acknowledgeFocusedPane()
        showSidebar()
        // In front, the sidebar says it.
        if notifies, needsUser, !NSApp.isActive, let state = activity[report.pane],
            let workspace = store.workspaceID(containing: report.pane).flatMap(store.workspace)
        {
            notifier.post(state, from: report.agent, in: report.pane, of: workspace)
        }
    }

    /// A finished turn in the pane the user is looking at needs nothing more
    /// from them.
    func acknowledgeFocusedPane() {
        guard NSApp.isActive, window?.isKeyWindow == true, let pane = store.selectedWorkspace?.focusedPane else {
            return
        }
        activity.acknowledge(pane)
    }

    /// The next pane in sidebar order after the focused one whose agent
    /// needs the user, coming back round to the focused pane last.
    var nextAgentNeedingUser: Pane.ID? {
        let order = store.sidebar.flatMap { $0.tree.panes.map(\.id) }
        return activity.next(after: store.selectedWorkspace?.focusedPane, in: order)
    }

    @objc func goToNextAgentNeedingUser(_ sender: Any?) {
        guard let pane = nextAgentNeedingUser else { return }
        reveal(pane)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        acknowledgeFocusedPane()
        showSidebar()
    }
}
