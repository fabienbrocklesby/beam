import AppKit
import BeamCore

// What terminals, menus and the sidebar ask the window to do.
extension MainWindowController: NSMenuItemValidation {
    // MARK: Terminal events

    func handle(_ event: TerminalEvent, from pane: Pane.ID) -> Bool {
        guard let workspace = store.workspaceID(containing: pane).flatMap(store.workspace) else { return false }
        let tree = workspace.tree
        let bounds = workspaceView(for: workspace.id)?.bounds ?? .zero

        switch event {
        case .focused:
            update(movesKeyboardFocus: false) { $0.focus(pane) }

        case .titleChanged(let title):
            paneViews[pane]?.title = title
            updateTitle()

        case .workingDirectoryChanged(let directory):
            LaunchTime.promptReached()
            paneViews[pane]?.directory = directory
            update { $0.updatePane(pane) { $0.workingDirectory = directory } }

        case .commandFinished:
            // The first command a pane's shell runs is the one Beam typed, so
            // once any command finishes, nothing Beam started is running.
            activity.forget(pane)
            update(movesKeyboardFocus: false) {
                $0.updatePane(pane) {
                    $0.command = nil
                    $0.agentSession = nil
                }
            }
            showSidebar()
            // It may have installed an agent.
            installedAgents.refresh()
            if updatePanes.remove(pane) != nil { updates.updateFinished() }

        case .closeRequested(let processAlive):
            confirmClose("Close this pane?", needed: processAlive) { [weak self] in
                self?.update { $0.closePane(pane) }
            }

        case .newSplit(let direction):
            var next = store
            guard let added = next.split(pane, toward: direction),
                let new = next.workspace(workspace.id)?.tree.pane(added)
            else { return false }
            adopt(new, in: workspace.id, splitFrom: paneViews[pane]?.terminal)
            update { $0 = next }

        case .focusSplit(let target):
            let neighbour: Pane.ID?
            switch target {
            case .previous: neighbour = tree.pane(before: pane)
            case .next: neighbour = tree.pane(after: pane)
            case .neighbour(let direction): neighbour = tree.neighbour(of: pane, toward: direction, in: bounds)
            }
            guard let neighbour else { return false }
            update { $0.focus(neighbour) }

        case .toggleSplitZoom:
            guard tree.panes.count > 1 else { return false }
            update { $0.toggleZoom(pane) }

        case .equalizeSplits:
            guard tree.panes.count > 1 else { return false }
            update { $0.modifyTree(containing: pane) { $0.equalize() } }

        case .resizeSplit(let direction, let points):
            guard tree.panes.count > 1 else { return false }
            update { store in
                store.modifyTree(containing: pane) {
                    $0.resize(
                        pane, toward: direction, by: points, in: bounds,
                        dividerThickness: WorkspaceView.dividerThickness,
                        minimumExtent: WorkspaceView.minimumPaneExtent)
                }
            }

        case .newWorkspace:
            chooseWorkspaceFolder()

        case .selectWorkspace(let target):
            switch target {
            case .position(let position): update { $0.select(at: position) }
            case .previous: update { $0.selectPrevious() }
            case .next: update { $0.selectNext() }
            case .last: update { $0.select(at: $0.unarchived.count - 1) }
            }

        case .closeWorkspace:
            closeWorkspace(workspace.id)

        case .closeWindow:
            window?.performClose(nil)
        }
        return true
    }

    private func chooseWorkspaceFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder for the new workspace."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.update { $0.open(folder: url.path) }
        }
    }

    private func closeWorkspace(_ id: Workspace.ID) {
        confirmClose("Close this workspace?", needed: needsConfirmClose(id)) { [weak self] in
            self?.update { $0.close(id) }
        }
    }

    // MARK: Sidebar commands

    func perform(_ command: SidebarViewController.Command, on id: Workspace.ID) {
        switch command {
        case .select:
            update { $0.select(id) }
        case .setPinned(let pinned):
            update { $0.setPinned(id, pinned) }
        case .setColor(let color):
            update { $0.setColor(id, color) }
        case .setArchived(true):
            confirmClose("Archive this workspace?", needed: needsConfirmClose(id)) { [weak self] in
                self?.update { $0.setArchived(id, true) }
            }
        case .setArchived(false):
            update { $0.setArchived(id, false) }
        case .close:
            closeWorkspace(id)
        case .move(let position):
            update { $0.moveWorkspace(id, to: position) }
        }
    }

    // MARK: Launcher

    /// Opens `entry` in a new pane in the selected workspace's folder, tiled
    /// beside the workspace's largest pane.
    func open(_ entry: LauncherEntry) {
        guard let id = store.selection else { return }
        let bounds = workspaceView(for: id)?.bounds ?? .zero
        update { $0.openPane(running: entry.command, in: id, bounds: bounds) }
    }

    /// Whether `entry` can open now: an agent needs to be installed.
    func canOpen(_ entry: LauncherEntry) -> Bool {
        guard store.selectedWorkspace != nil else { return false }
        guard case .agent(let agent) = entry else { return true }
        return installedAgents.agents.contains(agent)
    }

    // MARK: Menu actions

    /// Opens the `LauncherEntry` in the item's `representedObject`.
    @objc func openLauncherEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? LauncherEntry else { return }
        open(entry)
    }

    /// Runs the Ghostty keybinding action in the item's `representedObject`
    /// on the focused pane, the same path its key takes.
    @objc func performBindingAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String else { return }
        focusedPane?.terminal.performBindingAction(action)
    }

    @objc func toggleShowsArchived(_ sender: Any?) {
        update { $0.showsArchived.toggle() }
    }

    /// Opens the switcher near the top of the window, or closes it.
    @objc func toggleSwitcher(_ sender: Any?) {
        guard switcher == nil else {
            closeSwitcher()
            return
        }
        guard let window else { return }
        let controller = SwitcherViewController(items: switcherItems() + launcherItems())
        controller.onPick = { [weak self] target in
            self?.closeSwitcher()
            self?.go(to: target)
        }
        controller.onCancel = { [weak self] in self?.closeSwitcher() }
        let panel = SwitcherPanel(contentViewController: controller)
        panel.onResignKey = { [weak self] in self?.closeSwitcher() }

        // Centred, a little below the title bar; it grows downward as results
        // come in.
        let size = SwitcherViewController.size(rows: 0)
        let top = window.frame.minY + window.contentLayoutRect.maxY - 56
        panel.setFrame(
            NSRect(x: window.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
            display: false)
        switcher = panel
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeSwitcher() {
        guard let panel = switcher else { return }
        switcher = nil
        window?.removeChildWindow(panel)
        panel.orderOut(nil)
        window?.makeKey()
    }

    /// Every workspace the sidebar shows, each followed by its panes. A pane
    /// whose terminal has not started yet goes by its directory, and one
    /// whose agent has reported shows its state.
    private func switcherItems() -> [SwitcherViewController.Item] {
        store.sidebar.flatMap { workspace in
            let folder = (workspace.folder as NSString).abbreviatingWithTildeInPath
            let detail = [folder, branches[workspace.id]].compactMap { $0 }.joined(separator: " · ")
            let panes = workspace.tree.panes.map { pane in
                let directory = ((pane.workingDirectory ?? workspace.folder) as NSString).abbreviatingWithTildeInPath
                return SwitcherViewController.Item(
                    target: .pane(pane.id), title: paneViews[pane.id]?.title ?? directory, detail: workspace.name,
                    symbol: activity[pane.id]?.symbolName ?? "terminal")
            }
            let symbol = workspace.isArchived ? "archivebox" : workspace.isPinned ? "pin" : "folder"
            let item = SwitcherViewController.Item(
                target: .workspace(workspace.id), title: workspace.name, detail: detail, symbol: symbol)
            return [item] + panes
        }
    }

    /// What the launcher can open in the selected workspace, after
    /// everything there is to go to.
    private func launcherItems() -> [SwitcherViewController.Item] {
        guard let workspace = store.selectedWorkspace else { return [] }
        return LauncherEntry.all.filter(canOpen).map { entry in
            SwitcherViewController.Item(
                target: .launch(entry), title: entry.title, detail: workspace.name, symbol: "plus.rectangle")
        }
    }

    private func go(to target: SwitcherViewController.Item.Target) {
        switch target {
        case .launch(let entry):
            open(entry)
        case .workspace(let id):
            update { $0.select(id) }
        case .pane(let pane):
            reveal(pane)
        }
    }

    /// Selects `pane`'s workspace and focuses it.
    func reveal(_ pane: Pane.ID) {
        guard let workspace = store.workspaceID(containing: pane) else { return }
        update {
            $0.select(workspace)
            $0.focus(pane)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(performBindingAction(_:)):
            // Tagged items select the workspace at that sidebar position.
            if menuItem.tag > 0 {
                let unarchived = store.unarchived
                guard unarchived.indices.contains(menuItem.tag - 1) else {
                    menuItem.title = "Workspace \(menuItem.tag)"
                    return false
                }
                menuItem.title = unarchived[menuItem.tag - 1].name
            }
            return focusedPane != nil
        case #selector(openLauncherEntry(_:)):
            return (menuItem.representedObject as? LauncherEntry).map(canOpen) ?? false
        case #selector(goToNextAgentNeedingUser(_:)):
            return nextAgentNeedingUser != nil
        case #selector(updateAgent(_:)), #selector(updateAllAgents(_:)):
            return canUpdate(menuItem)
        case #selector(toggleShowsArchived(_:)):
            menuItem.state = store.showsArchived ? .on : .off
            return true
        default:
            return true
        }
    }
}
