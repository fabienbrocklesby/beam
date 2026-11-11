import AppKit
import BeamCore
import os

/// Beam's one window: the workspace sidebar beside the selected workspace.
///
/// Owns the `WorkspaceStore`. Every change goes through `update`, which saves
/// it and then brings the views in line with the store: panes that left it
/// have their sessions ended and their terminals freed, the selected
/// workspace's terminals are created on first show, and the other
/// workspaces are hidden.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let ghostty: GhosttyApp
    private var style: GhosttyApp.SplitStyle
    private(set) var store = WorkspaceStore()
    private let saver: StateSaver
    let installedAgents: InstalledAgents
    let updates: AgentUpdates
    /// Panes Beam typed an update into, until it finishes.
    var updatePanes: Set<Pane.ID> = []
    /// How agents started here report their state; nil when they cannot.
    private let hooks: AgentHooks?
    /// Runs every pane's session; nil when panes run their shell themselves.
    private let daemon: DaemonClient?
    /// Which restored panes attach to a session that outlived the last Beam.
    private let restore: SessionRestore
    /// What each pane's agent last reported.
    var activity = AgentActivity() {
        didSet {
            notifier.withdraw { activity[$0]?.needsAttention == true }
            for (id, view) in paneViews { view.agent = activity[id] }
        }
    }
    let notifier: AgentNotifier

    private let sidebar = SidebarViewController()
    private let launcher = LauncherToolbar()
    private let content = NSView()
    private var workspaceViews: [Workspace.ID: WorkspaceView] = [:]
    private(set) var paneViews: [Pane.ID: PaneView] = [:]
    private var branchWatchers: [Workspace.ID: GitBranchWatcher] = [:]
    private(set) var branches: [Workspace.ID: String] = [:]
    /// The Cmd+P switcher while it is open.
    var switcher: SwitcherPanel?

    /// Opens the window on `store`, which has a workspace selected.
    init(
        ghostty: GhosttyApp, store restored: WorkspaceStore, saver: StateSaver, installedAgents: InstalledAgents,
        updates: AgentUpdates, updatesMenu: NSMenu, hooks: AgentHooks?, daemon: DaemonClient?, restore: SessionRestore,
        notifier: AgentNotifier
    ) {
        self.ghostty = ghostty
        self.saver = saver
        self.installedAgents = installedAgents
        self.updates = updates
        self.hooks = hooks
        self.daemon = daemon
        self.restore = restore
        self.notifier = notifier
        style = ghostty.splitStyle
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .disallowed
        // Beam restores its own workspaces; AppKit's window restoration would
        // only fight that.
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self

        let contentController = NSViewController()
        contentController.view = content
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: contentController))
        window.contentViewController = split
        window.toolbar = launcher.toolbar
        window.toolbarStyle = .unifiedCompact
        // The title bar takes the terminal's background, so it reads as the
        // top of the terminal rather than a band across it.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = style.background
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        window.setFrameAutosaveName("Main")

        sidebar.onCommand = { [weak self] command, id in self?.perform(command, on: id) }
        sidebar.onNewWorkspace = { [weak self] in self?.chooseWorkspaceFolder() }
        sidebar.onFinishRename = { [weak self] in
            self?.window?.makeFirstResponder(self?.focusedPane?.terminal)
        }
        launcher.onLaunch = { [weak self] entry in self?.open(entry) }
        launcher.show(installed: installedAgents.agents)
        installedAgents.onChange = { [weak self] in
            guard let self else { return }
            launcher.show(installed: self.installedAgents.agents)
        }
        launcher.updatesMenu = updatesMenu
        updates.panesRunning = { [weak self] agent in self?.panes(running: agent) ?? [] }
        showUpdates()
        update { $0 = restored }
        // After the restore, so a click that launched Beam finds its pane.
        notifier.onOpen = { [weak self] pane in
            self?.showWindow(nil)
            NSApp.activate()
            self?.reveal(pane)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    var focusedPane: PaneView? {
        store.selectedWorkspace?.focusedPane.flatMap { paneViews[$0] }
    }

    func workspaceView(for id: Workspace.ID) -> WorkspaceView? { workspaceViews[id] }

    /// Shows the title bar's update button while an update waits.
    func showUpdates() {
        launcher.show(updates: updates.available.count)
    }

    /// Restyles the panes from the current config, after a reload or a
    /// switch between light and dark changed the theme.
    func applyConfig() {
        style = ghostty.splitStyle
        window?.backgroundColor = style.background
        for view in workspaceViews.values { view.style = style }
        for view in paneViews.values { view.style = style }
    }

    // MARK: Changing the store

    /// Applies `change` to the store and brings the views in line.
    /// `movesKeyboardFocus` makes the focused pane's terminal first
    /// responder; it is false when the change records a terminal that is
    /// already becoming first responder.
    func update(movesKeyboardFocus: Bool = true, _ change: (inout WorkspaceStore) -> Void) {
        var next = store
        change(&next)
        guard next != store else { return }
        // Only leaving the store ends a session: a terminal freed with the
        // window, as Beam quits, leaves it running.
        let closed = Self.paneIDs(in: store).subtracting(Self.paneIDs(in: next))
        store = next
        saver.save(store)
        for pane in closed { daemon?.send(.end(pane: pane)) }
        updatePanes.subtract(closed)
        reconcile(movesKeyboardFocus: movesKeyboardFocus)
    }

    private static func paneIDs(in store: WorkspaceStore) -> Set<Pane.ID> {
        Set(store.workspaces.flatMap { $0.tree.panes.map(\.id) })
    }

    /// Adds the view for a pane the store is about to gain, so it can start
    /// from `parent`'s terminal settings instead of being created plain.
    func adopt(_ pane: Pane, in workspace: Workspace.ID, splitFrom parent: TerminalView?) {
        paneViews[pane.id] = makePaneView(pane, in: workspace, splitFrom: parent)
    }

    private func reconcile(movesKeyboardFocus: Bool) {
        let live = Self.paneIDs(in: store)
        for (id, view) in paneViews where !live.contains(id) {
            view.removeFromSuperview()
            paneViews[id] = nil
            activity.forget(id)
        }
        for (id, view) in workspaceViews where store.workspace(id) == nil {
            view.removeFromSuperview()
            workspaceViews[id] = nil
        }
        for id in branchWatchers.keys where store.workspace(id) == nil {
            branchWatchers[id] = nil
            branches[id] = nil
        }
        for workspace in store.workspaces where branchWatchers[workspace.id] == nil {
            let id = workspace.id
            branchWatchers[id] = GitBranchWatcher(folder: workspace.folder) { [weak self] branch in
                self?.branches[id] = branch
                self?.showSidebar()
            }
        }

        guard let selected = store.selectedWorkspace else {
            // Nothing is open: the window goes, and with it the app.
            window?.close()
            return
        }

        // Only the selected workspace gets terminals, so the others cost
        // nothing until they are shown.
        var failed: [Pane.ID] = []
        for pane in selected.tree.panes where paneViews[pane.id] == nil {
            if let view = makePaneView(pane, in: selected.id, splitFrom: nil) {
                paneViews[pane.id] = view
            } else {
                failed.append(pane.id)
            }
        }
        let workspaceView = workspaceViews[selected.id] ?? makeWorkspaceView(selected.id)
        for (id, view) in workspaceViews {
            view.isHidden = id != selected.id
        }
        workspaceView.show(selected, views: paneViews)
        acknowledgeFocusedPane()
        showSidebar()
        updateTitle()

        if movesKeyboardFocus, let terminal = focusedPane?.terminal, window?.firstResponder !== terminal {
            window?.makeFirstResponder(terminal)
        }
        if !failed.isEmpty {
            update { store in
                for pane in failed { store.closePane(pane) }
            }
        }
    }

    func showSidebar() {
        let agents = store.sidebar.reduce(into: [Workspace.ID: AgentState]()) { agents, workspace in
            agents[workspace.id] = activity.summary(of: workspace.tree.panes.map(\.id))
        }
        sidebar.show(store.sidebar, branches: branches, agents: agents, selection: store.selection)
    }

    /// The selected workspace's name, with its focused pane's title below.
    func updateTitle() {
        guard let selected = store.selectedWorkspace else { return }
        window?.title = selected.name
        window?.subtitle = focusedPane?.displayTitle ?? ""
    }

    private func makeWorkspaceView(_ id: Workspace.ID) -> WorkspaceView {
        let view = WorkspaceView(style: style)
        view.onRatioChange = { [weak self] path, ratio in
            self?.update { $0.modifyTree(of: id) { $0.setRatio(ratio, at: path) } }
        }
        view.onEqualize = { [weak self] path in
            self?.update { $0.modifyTree(of: id) { $0.equalize(at: path) } }
        }
        view.onMovePane = { [weak self] pane, target, drop in
            self?.update { $0.movePane(pane, onto: target, drop) }
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        let safeArea = content.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            view.topAnchor.constraint(equalTo: safeArea.topAnchor),
            view.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
        ])
        workspaceViews[id] = view
        return view
    }

    private func makePaneView(_ pane: Pane, in workspace: Workspace.ID, splitFrom parent: TerminalView?) -> PaneView? {
        // Typed into the user's own shell rather than run in its place, so the
        // command sees the PATH and variables their rc files set up, which
        // Beam's own environment lacks when it starts from Finder, and the
        // pane is back at a prompt when the command exits. Never into a live
        // session, where it would land in whatever is running.
        let options = TerminalView.Options(
            command: daemon?.surfaceCommand,
            workingDirectory: pane.workingDirectory,
            initialInput: restore.initialCommand(for: pane).map { (hooks?.typed($0) ?? $0) + "\r" },
            environment: PaneEnvironment.variables(pane: pane.id, workspace: workspace, hooks: hooks)
                .merging(daemon?.paneEnvironment ?? [:]) { $1 })
        guard let terminal = TerminalView(app: ghostty, options: options, splitFrom: parent) else {
            Logger.app.error("could not start a terminal for pane \(pane.id, privacy: .public)")
            return nil
        }
        let id = pane.id
        terminal.onEvent = { [weak self] event in self?.handle(event, from: id) ?? false }
        let view = PaneView(id: id, terminal: terminal, style: style)
        view.directory = pane.workingDirectory
        view.agent = activity[id]
        return view
    }

    // MARK: NSWindowDelegate

    /// Closing the window quits Beam, which leaves every session running, so
    /// it only asks when the panes run their shells themselves.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard daemon?.isConnected != true else { return true }
        let running = paneViews.values.contains { $0.terminal.needsConfirmClose }
        guard running else { return true }
        confirmClose("Close the window?", needed: true) { [weak self] in self?.window?.close() }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // Free every terminal now, so they detach from their sessions (or,
        // without beamd, end their shells) with the window rather than
        // whenever the app exits.
        for view in paneViews.values { view.removeFromSuperview() }
        paneViews = [:]
        for view in workspaceViews.values { view.removeFromSuperview() }
        workspaceViews = [:]
    }

    // MARK: Confirming

    /// Runs `close` now, or once the user agrees when `needed` says it would
    /// end a running process.
    func confirmClose(_ message: String, needed: Bool, _ close: @escaping () -> Void) {
        guard needed, let window else {
            close()
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "A process is still running. Closing will end it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { close() }
        }
    }

    func needsConfirmClose(_ workspace: Workspace.ID) -> Bool {
        store.workspace(workspace)?.tree.panes.contains { paneViews[$0.id]?.terminal.needsConfirmClose == true }
            ?? false
    }
}
