import BeamCore
import CoreGraphics
import Testing

struct SessionRestoreTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// A store with a shell pane and an agent pane, as a relaunch finds it.
    private func relaunched() -> (WorkspaceStore, shell: Pane, agent: Pane) {
        var store = WorkspaceStore()
        let workspace = store.open(folder: "/project")
        let agent = store.openPane(running: "claude", in: workspace, bounds: bounds)
        if let agent { store.updatePane(agent) { $0.agentSession = "abc" } }
        store.prepareForLaunch(home: "/home") { _ in true }
        let panes = store.workspace(workspace)?.tree.panes ?? []
        return (store, panes[0], panes[1])
    }

    @Test func aPaneWhoseSessionLivesTypesNothing() {
        let (_, shell, agent) = relaunched()
        let restore = SessionRestore(live: [shell.id, agent.id])
        #expect(restore.initialCommand(for: agent) == nil)
        #expect(restore.initialCommand(for: shell) == nil)
    }

    @Test func aPaneWhoseSessionHasGoneTypesItsResumeCommand() {
        let (_, shell, agent) = relaunched()
        let restore = SessionRestore(live: [])
        #expect(restore.initialCommand(for: agent) == "claude --resume abc")
        #expect(restore.initialCommand(for: shell) == nil)
    }

    @Test func aNewPaneTypesItsCommand() {
        let restore = SessionRestore(live: [Pane.ID()])
        #expect(restore.initialCommand(for: Pane(command: "codex")) == "codex")
    }

    @Test func liveSessionsNoPaneWantsAreOrphans() {
        let (store, shell, agent) = relaunched()
        let orphan = Pane.ID()
        let restore = SessionRestore(live: [shell.id, orphan, agent.id])
        #expect(restore.orphans(in: store, stateLoaded: true) == [orphan])
    }

    /// Without a state file that loaded, Beam cannot tell whose they are.
    @Test func nothingIsAnOrphanWhenTheStateFileDidNotLoad() {
        let (store, shell, _) = relaunched()
        let restore = SessionRestore(live: [shell.id, Pane.ID()])
        #expect(restore.orphans(in: store, stateLoaded: false).isEmpty)
    }
}
