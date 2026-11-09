import AppKit
import BeamCore
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ghostty: GhosttyApp
    private let saver = StateSaver(file: .standard)
    private let installedAgents = InstalledAgents()
    private let updates: AgentUpdates
    private let agentsMenu: AgentsMenu
    private let notifier = AgentNotifier()
    private var windowController: MainWindowController?
    /// Runs every pane's session; nil when beamd could not be reached, and
    /// then panes run their shell themselves and agents start without hooks.
    private var daemon: DaemonClient?
    /// The saved store, held until beamd says which of its sessions live.
    private var restoring: (store: WorkspaceStore, loaded: Bool)?

    init(ghostty: GhosttyApp) {
        self.ghostty = ghostty
        updates = AgentUpdates(installedAgents: installedAgents)
        agentsMenu = AgentsMenu(updates: updates)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(ghostty: ghostty, agents: agentsMenu)
        // Menus show the keys the config binds, so they are rebuilt with it.
        ghostty.onConfigChange = { [weak self] in
            guard let self else { return }
            NSApp.mainMenu = MainMenu.make(ghostty: ghostty, agents: agentsMenu)
            windowController?.applyConfig()
        }
        updates.onChange = { [weak self] in
            self?.agentsMenu.refresh()
            self?.windowController?.showUpdates()
        }
        installedAgents.start { [updates] in updates.start() }
        StateSaver.load(.standard) { [self] store, loaded in
            guard let daemon = DaemonClient(bundle: .main) else {
                openWindow(store, sessions: [], stateLoaded: loaded)
                return
            }
            self.daemon = daemon
            restoring = (store, loaded)
            daemon.onEvent = { [weak self] event in self?.handle(event) }
            daemon.onClose = { [weak self] in self?.daemonClosed() }
        }
    }

    private func handle(_ event: ControlEvent) {
        switch event {
        case .sessions(let sessions):
            guard let restoring else { return }
            self.restoring = nil
            openWindow(restoring.store, sessions: sessions, stateLoaded: restoring.loaded)
        case .report(let report):
            windowController?.handle(report)
        }
    }

    /// beamd went away. Before it answered, the panes start without it.
    private func daemonClosed() {
        guard let restoring else { return }
        self.restoring = nil
        daemon = nil
        openWindow(restoring.store, sessions: [], stateLoaded: restoring.loaded)
    }

    /// Rebuilds the saved workspaces: panes with a live session attach to it,
    /// what their agents reported while Beam was not running shows in the
    /// sidebar, and sessions no pane wants are ended.
    private func openWindow(_ store: WorkspaceStore, sessions: [ControlEvent.Session], stateLoaded: Bool) {
        let restore = SessionRestore(live: sessions.map(\.pane))
        let controller = MainWindowController(
            ghostty: ghostty, store: store, saver: saver, installedAgents: installedAgents, updates: updates,
            updatesMenu: agentsMenu.makeMenu(pullDown: true), hooks: daemon == nil ? nil : agentHooks(), daemon: daemon,
            restore: restore, notifier: notifier)
        windowController = controller
        for report in sessions.flatMap(\.reports) { controller.handle(report, notifies: false) }
        for pane in restore.orphans(in: controller.store, stateLoaded: stateLoaded) {
            daemon?.send(.end(pane: pane))
        }
        controller.showWindow(nil)
        NSApp.activate()
    }

    @objc func openSettings(_ sender: Any?) {
        ghostty.openSettings()
    }

    @objc func reloadConfiguration(_ sender: Any?) {
        ghostty.reloadConfig()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting leaves every session running in beamd, so it only asks when
    /// the panes run their shells themselves.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard daemon?.isConnected != true, ghostty.needsConfirmQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Beam?"
        alert.informativeText = "A process is still running in a pane. Quitting will end it."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Beam > Quit and End Sessions: ends every pane's session, then quits.
    @objc func quitAndEndSessions(_ sender: Any?) {
        guard let daemon, daemon.isConnected else { return NSApp.terminate(sender) }
        if ghostty.needsConfirmQuit {
            let alert = NSAlert()
            alert.messageText = "End every session and quit?"
            alert.informativeText = "A process is still running in a pane. Ending its session will end it."
            alert.addButton(withTitle: "End Sessions and Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // Terminating never returns to the run loop, so the panes closing as
        // their sessions end cannot reach the saved state.
        daemon.send(.endAll)
        NSApp.terminate(sender)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saver.flush()
    }

    /// Hooks for the agents Beam starts, which report through beamd.
    private func agentHooks() -> AgentHooks? {
        let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/beam").path
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            Logger.app.error("no beam helper at \(helper, privacy: .public), so agents start without hooks")
            return nil
        }
        return AgentHooks(helper: helper)
    }
}
