import AppKit
import BeamCore

// Updating agent CLIs from the Agents menu.
extension MainWindowController {
    /// Updates the `Agent` in the item's `representedObject`.
    @objc func updateAgent(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? Agent, let command = updates.updates[agent]?.command else {
            return
        }
        runUpdate(command)
    }

    /// Runs every waiting update in one pane, each whether or not the one
    /// before it worked.
    @objc func updateAllAgents(_ sender: Any?) {
        let commands = updates.available.compactMap { updates.updates[$0]?.command }
        guard !commands.isEmpty else { return }
        runUpdate(commands.joined(separator: "; "))
    }

    /// Types `command` into a new pane beside the selected workspace's
    /// largest pane, so the user sees its output and answers any prompt. It
    /// runs in the home folder, where mise reads the same config as the login
    /// shell whose `PATH` found the agents.
    private func runUpdate(_ command: String) {
        guard let id = store.selection else { return }
        let bounds = workspaceView(for: id)?.bounds ?? .zero
        var opened: Pane.ID?
        update { opened = $0.openPane(running: command, in: id, folder: NSHomeDirectory(), bounds: bounds) }
        if let opened { updatePanes.insert(opened) }
    }

    /// The panes running `agent` as their command.
    func panes(running agent: Agent) -> Set<Pane.ID> {
        let panes = store.workspaces.flatMap(\.tree.panes)
        return Set(panes.filter { $0.command.flatMap(Agent.init(command:)) == agent }.map(\.id))
    }

    /// Whether the update in `menuItem` can run now.
    func canUpdate(_ menuItem: NSMenuItem) -> Bool {
        guard store.selectedWorkspace != nil else { return false }
        switch menuItem.action {
        case #selector(updateAgent(_:)):
            return (menuItem.representedObject as? Agent).flatMap { updates.updates[$0]?.available } != nil
        default:
            return !updates.available.isEmpty
        }
    }
}
