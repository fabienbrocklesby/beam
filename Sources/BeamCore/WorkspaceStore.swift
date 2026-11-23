import Foundation

/// Every workspace, which one is selected, and the rules for opening,
/// closing and ordering them.
///
/// Archiving hides a workspace until it is shown or selected again and keeps
/// its panes, so whatever runs in them carries on. A workspace with no panes
/// is pinned or archived, and starts a shell when selected again; any other
/// closes with its last pane. Closing a workspace itself removes it, pinned
/// or not.
public struct WorkspaceStore: Codable, Equatable, Sendable {
    /// In the order the user arranged them, new ones last.
    public private(set) var workspaces: [Workspace] = []
    public private(set) var selection: Workspace.ID?
    public var showsArchived = false
    /// Whether panes show a tray of the files an agent's reply named. Off
    /// until the user turns it on.
    public var showsPreviews = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case workspaces, selection, showsArchived, showsPreviews
    }

    /// Files from Beam 0.1 have no `showsPreviews`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaces = try container.decode([Workspace].self, forKey: .workspaces)
        selection = try container.decodeIfPresent(Workspace.ID.self, forKey: .selection)
        showsArchived = try container.decode(Bool.self, forKey: .showsArchived)
        showsPreviews = try container.decodeIfPresent(Bool.self, forKey: .showsPreviews) ?? false
    }

    public func workspace(_ id: Workspace.ID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    public var selectedWorkspace: Workspace? { selection.flatMap(workspace) }

    public func workspaceID(containing pane: Pane.ID) -> Workspace.ID? {
        workspaces.first { $0.tree.contains(pane) }?.id
    }

    /// Sidebar order: pinned, then the rest, then archived when shown, each
    /// group in the order of `workspaces`.
    public var sidebar: [Workspace] {
        unarchived + (showsArchived ? workspaces.filter(\.isArchived) : [])
    }

    /// The sidebar without archived rows, which come last in it, so positions
    /// match. Switching by number or to the next or previous walks this:
    /// stepping onto an archived row would bring it back.
    public var unarchived: [Workspace] {
        let live = workspaces.filter { !$0.isArchived }
        return live.filter(\.isPinned) + live.filter { !$0.isPinned }
    }

    // MARK: Opening and selecting

    /// Selects the first workspace for `folder`, creating one if there is
    /// none.
    @discardableResult
    public mutating func open(folder: String) -> Workspace.ID {
        let folder = (folder as NSString).standardizingPath
        if let existing = workspaces.first(where: { $0.folder == folder }) {
            select(existing.id)
            return existing.id
        }
        return create(folder: folder)
    }

    /// Creates a workspace for `folder`, whether or not one is open there,
    /// and selects it. A name another workspace has gets a number, as in
    /// `beam 2`, and keeps it until renamed.
    @discardableResult
    public mutating func create(folder: String) -> Workspace.ID {
        add(Workspace(folder: (folder as NSString).standardizingPath))
    }

    /// Appends `workspace`, numbering its name while another workspace has
    /// it, and selects it.
    @discardableResult
    private mutating func add(_ workspace: Workspace) -> Workspace.ID {
        var workspace = workspace
        let base = workspace.name
        let taken = Set(workspaces.map(\.name))
        var number = 2
        while taken.contains(workspace.name) {
            workspace.name = "\(base) \(number)"
            number += 1
        }
        workspaces.append(workspace)
        selection = workspace.id
        return workspace.id
    }

    /// Selects `id`, bringing it back from the archive and starting a shell in
    /// it if it has none.
    public mutating func select(_ id: Workspace.ID) {
        guard let index = index(of: id) else { return }
        workspaces[index].isArchived = false
        workspaces[index].reopen()
        selection = id
    }

    /// Selects the workspace at `position` in `unarchived`.
    public mutating func select(at position: Int) {
        let unarchived = unarchived
        guard unarchived.indices.contains(position) else { return }
        select(unarchived[position].id)
    }

    /// Moves `id` into the pinned or the unpinned section, to the gap above
    /// the row at `position` in that section as the sidebar shows it, as a
    /// table reports a drop; the section's count is its end. The section
    /// decides pinning, since the end of one and the start of the other are
    /// the same place in the list. Archived workspaces do not move.
    public mutating func moveWorkspace(_ id: Workspace.ID, pinned: Bool, to position: Int) {
        let rows = unarchived
        guard var moved = rows.first(where: { $0.id == id }) else { return }
        var section = rows.filter { $0.isPinned == pinned }
        var index = position
        if let from = section.firstIndex(where: { $0.id == id }) {
            if index > from { index -= 1 }
            section.remove(at: from)
        }
        moved.isPinned = pinned
        section.insert(moved, at: min(max(index, 0), section.count))
        let others = rows.filter { $0.isPinned != pinned && $0.id != id }
        let ordered = pinned ? section + others : others + section
        guard ordered != rows else { return }
        workspaces = ordered + workspaces.filter(\.isArchived)
    }

    public mutating func selectNext() { selectAdjacent(offset: 1) }

    public mutating func selectPrevious() { selectAdjacent(offset: -1) }

    private mutating func selectAdjacent(offset: Int) {
        let ids = unarchived.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) } ?? 0
        select(ids[(current + offset + ids.count) % ids.count])
    }

    /// Readies a saved store for a new launch, where every pane starts a
    /// fresh shell. A pane that was running an agent resumes its last
    /// session; any other command runs again as it was. Panes whose directory
    /// is gone start in their workspace folder, or `home` when that is gone
    /// too. When no workspace was open, the first in the sidebar opens, or a
    /// new one for `home`.
    public mutating func prepareForLaunch(home: String, directoryExists: (String) -> Bool) {
        for index in workspaces.indices {
            let folder = workspaces[index].folder
            for pane in workspaces[index].tree.panes {
                workspaces[index].tree.updatePane(pane.id) { pane in
                    pane.command = pane.command.map { Agent.resuming($0, session: pane.agentSession) }
                    if let directory = pane.workingDirectory, !directoryExists(directory) {
                        pane.workingDirectory = directoryExists(folder) ? folder : home
                    }
                }
            }
        }
        if let selected = selectedWorkspace, !selected.tree.isEmpty { return }
        if let first = unarchived.first {
            select(first.id)
        } else {
            open(folder: home)
        }
    }

    // MARK: Closing

    /// Closes workspace `id` and every pane in it. A pinned one goes too:
    /// pinning keeps a workspace through its last pane closing, not through
    /// being closed itself.
    public mutating func close(_ id: Workspace.ID) {
        guard let index = index(of: id) else { return }
        let sidebarBefore = sidebar
        workspaces.remove(at: index)
        moveSelection(awayFrom: id, in: sidebarBefore)
    }

    /// Archives `id` or brings it back. Its panes stay as they are: only a
    /// pane leaving the store ends its session, so an archived workspace's
    /// agents keep working out of sight.
    public mutating func setArchived(_ id: Workspace.ID, _ archived: Bool) {
        guard let index = index(of: id) else { return }
        guard archived else {
            workspaces[index].isArchived = false
            return
        }
        let sidebarBefore = sidebar
        workspaces[index].isArchived = true
        moveSelection(awayFrom: id, in: sidebarBefore)
    }

    /// When `id` was selected, selects the nearest open workspace after it in
    /// `sidebar`, else before it, else nothing.
    private mutating func moveSelection(awayFrom id: Workspace.ID, in sidebar: [Workspace]) {
        guard selection == id else { return }
        let position = sidebar.firstIndex { $0.id == id } ?? sidebar.endIndex
        let nearest = sidebar.dropFirst(position + 1) + sidebar[..<position].reversed()
        let open = workspaces.filter { !$0.isArchived && !$0.tree.isEmpty }.map(\.id)
        selection = nearest.first { open.contains($0.id) }?.id
    }

    // MARK: Attributes

    public mutating func setPinned(_ id: Workspace.ID, _ pinned: Bool) {
        modify(id) { $0.isPinned = pinned }
    }

    public mutating func setColor(_ id: Workspace.ID, _ color: Workspace.Color?) {
        modify(id) { $0.color = color }
    }

    /// Renames `id` to `name` without the spaces around it. An empty name is
    /// the folder's again.
    public mutating func rename(_ id: Workspace.ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        modify(id) { $0.name = name.isEmpty ? $0.folderName : name }
    }

    // MARK: Panes

    public mutating func focus(_ pane: Pane.ID) {
        modifyWorkspace(containing: pane) { workspace in
            workspace.focusedPane = pane
            if let zoomed = workspace.tree.zoomed, zoomed != pane { workspace.tree.unzoom() }
        }
    }

    public mutating func updatePane(_ pane: Pane.ID, _ update: (inout Pane) -> Void) {
        modifyWorkspace(containing: pane) { $0.tree.updatePane(pane, update) }
    }

    /// Splits `pane`, starting the new pane in the workspace folder, and
    /// focuses it. When Ghostty's `window-inherit-working-directory` is on,
    /// the terminal starts in `pane`'s live directory instead and reports it
    /// back, so the folder only counts when inheritance is off.
    @discardableResult
    public mutating func split(_ pane: Pane.ID, toward direction: SplitTree.Direction) -> Pane.ID? {
        var added: Pane.ID?
        modifyWorkspace(containing: pane) { workspace in
            let new = Pane(workingDirectory: workspace.folder)
            workspace.tree.split(pane, toward: direction, inserting: new)
            workspace.focusedPane = new.id
            added = new.id
        }
        return added
    }

    /// Opens a pane in workspace `id`'s folder, or in `folder`, beside its
    /// largest pane (see `SplitTree.tile`) and focuses it. `command`, when
    /// set, is typed into the pane's shell as it starts. The viewer keeps
    /// its column: when it is the only pane, the new one goes on its left.
    @discardableResult
    public mutating func openPane(
        running command: String?, in id: Workspace.ID, folder: String? = nil, bounds: CGRect
    ) -> Pane.ID? {
        guard let index = index(of: id) else { return nil }
        let pane = Pane(workingDirectory: folder ?? workspaces[index].folder, command: command)
        let viewer = workspaces[index].viewer
        workspaces[index].tree.tile(pane, in: bounds, avoiding: viewer)
        if !workspaces[index].tree.contains(pane.id) {
            workspaces[index].tree.insert(pane, atEdge: .left, fraction: 0.5)
        }
        workspaces[index].focusedPane = pane.id
        return pane.id
    }

    /// Opens `command` in workspace `id` as the launcher does. While the
    /// workspace is nothing but the shell it started and that shell is
    /// untouched, the command takes the shell's place, so a new workspace
    /// goes straight to its agent. Otherwise, and for a plain shell, it
    /// opens in a new pane (see `openPane`).
    @discardableResult
    public mutating func launch(_ command: String?, in id: Workspace.ID, bounds: CGRect) -> Pane.ID? {
        guard let index = index(of: id) else { return nil }
        guard let command, let shell = workspaces[index].untouchedShell,
            workspaces[index].tree.panes.map(\.id) == [shell]
        else { return openPane(running: command, in: id, bounds: bounds) }
        let pane = Pane(workingDirectory: workspaces[index].folder, command: command)
        workspaces[index].tree = SplitTree(pane)
        workspaces[index].focusedPane = pane.id
        workspaces[index].untouchedShell = nil
        return pane.id
    }

    /// Records that `pane`'s shell is no longer as it started: something
    /// was typed into it or ran in it, so the launcher leaves it be.
    public mutating func markUsed(_ pane: Pane.ID) {
        modifyWorkspace(containing: pane) { workspace in
            if workspace.untouchedShell == pane { workspace.untouchedShell = nil }
        }
    }

    // MARK: Documents

    /// Shows the file at `path` in the viewer of the workspace holding
    /// `pane`, or in a new one: a full height column on the workspace's
    /// right edge, half the width beside one pane and 40% beside more.
    /// Focus stays where it was, so the user keeps typing to the agent that
    /// named the file. A zoom that would hide the viewer ends.
    ///
    /// - Returns: The viewer, or nil when no workspace holds `pane`.
    @discardableResult
    public mutating func showDocument(_ path: String, from pane: Pane.ID) -> Pane.ID? {
        let path = (path as NSString).standardizingPath
        guard let index = workspaces.firstIndex(where: { $0.tree.contains(pane) }) else { return nil }
        if let viewer = workspaces[index].viewer {
            if workspaces[index].tree.pane(viewer)?.document != path {
                workspaces[index].tree.updatePane(viewer) { $0.document = path }
            }
            if let zoomed = workspaces[index].tree.zoomed, zoomed != viewer { workspaces[index].tree.unzoom() }
            return viewer
        }
        let viewer = Pane(document: path)
        insertColumn(viewer, inWorkspaceAt: index)
        workspaces[index].viewer = viewer.id
        return viewer.id
    }

    /// Adds `pane` as a full height column on the right edge of the
    /// workspace at `index`, half the width beside one pane and 40% beside
    /// more.
    private mutating func insertColumn(_ pane: Pane, inWorkspaceAt index: Int) {
        let fraction = workspaces[index].tree.panes.count == 1 ? 0.5 : 0.4
        workspaces[index].tree.insert(pane, atEdge: .right, fraction: fraction)
    }

    /// Whether `pane` can move into workspace `target`: only a document,
    /// into another workspace that is not archived. A terminal stays, since
    /// its processes were started with its workspace's ID.
    public func canMovePane(_ pane: Pane.ID, toWorkspace target: Workspace.ID) -> Bool {
        guard let source = workspaceID(containing: pane), source != target,
            let destination = workspace(target), !destination.isArchived
        else { return false }
        return workspace(source)?.tree.pane(pane)?.document != nil
    }

    /// Moves the document pane `pane` into workspace `target` as a column
    /// on its right edge, sized as a new viewer is, and selects `target`
    /// with the pane focused. The pane becomes the viewer there when there
    /// is none. Its old workspace loses it as `closePane` has it, so one a
    /// file from Finder opened closes.
    public mutating func movePane(_ pane: Pane.ID, toWorkspace target: Workspace.ID) {
        guard canMovePane(pane, toWorkspace: target),
            let moved = workspaceID(containing: pane).flatMap(workspace)?.tree.pane(pane)
        else { return }
        closePane(pane)
        guard let index = index(of: target) else { return }
        insertColumn(moved, inWorkspaceAt: index)
        if workspaces[index].viewer == nil { workspaces[index].viewer = pane }
        workspaces[index].focusedPane = pane
        select(target)
    }

    /// Opens the file at `path` as Finder asks: a pane already showing it
    /// is selected and focused; otherwise the file gets a new workspace in
    /// its folder, named after it, where it is the only pane.
    @discardableResult
    public mutating func openDocument(_ path: String) -> Pane.ID {
        let path = (path as NSString).standardizingPath
        for workspace in workspaces {
            if let pane = workspace.tree.panes.first(where: { $0.document == path }) {
                select(workspace.id)
                focus(pane.id)
                return pane.id
            }
        }
        let pane = Pane.ID()
        add(Workspace(document: path, pane: pane))
        return pane
    }

    /// Moves `pane` onto `target` as `drop` says and focuses it. Both must be
    /// in the same workspace.
    public mutating func movePane(_ pane: Pane.ID, onto target: Pane.ID, _ drop: SplitTree.Drop) {
        modifyWorkspace(containing: pane) { workspace in
            guard pane != target, workspace.tree.contains(target) else { return }
            workspace.tree.move(pane, onto: target, drop)
            workspace.focusedPane = pane
        }
    }

    public mutating func toggleZoom(_ pane: Pane.ID) {
        modifyWorkspace(containing: pane) { $0.tree.toggleZoom(pane) }
    }

    /// Changes the tree holding `pane` in ways that keep its panes, such as
    /// ratios and equalizing.
    public mutating func modifyTree(containing pane: Pane.ID, _ change: (inout SplitTree) -> Void) {
        modifyWorkspace(containing: pane) { change(&$0.tree) }
    }

    /// Changes the tree of workspace `id` in ways that keep its panes.
    public mutating func modifyTree(of id: Workspace.ID, _ change: (inout SplitTree) -> Void) {
        modify(id) { change(&$0.tree) }
    }

    /// Removes `pane`. Focus moves to its neighbour if it had focus; the
    /// workspace closes with its last pane, unless pinned or archived, when
    /// it stays where it is with nothing open.
    public mutating func closePane(_ pane: Pane.ID) {
        guard let index = workspaces.firstIndex(where: { $0.tree.contains(pane) }) else { return }
        let neighbour = workspaces[index].tree.remove(pane)
        if workspaces[index].focusedPane == pane {
            workspaces[index].focusedPane = neighbour
        }
        if workspaces[index].viewer == pane {
            workspaces[index].viewer = nil
        }
        if workspaces[index].untouchedShell == pane {
            workspaces[index].untouchedShell = nil
        }
        guard workspaces[index].tree.isEmpty else { return }
        let id = workspaces[index].id
        if workspaces[index].isPinned || workspaces[index].isArchived {
            moveSelection(awayFrom: id, in: sidebar)
        } else {
            close(id)
        }
    }

    // MARK: Lookup

    private func index(of id: Workspace.ID) -> Int? {
        workspaces.firstIndex { $0.id == id }
    }

    private mutating func modify(_ id: Workspace.ID, _ change: (inout Workspace) -> Void) {
        guard let index = index(of: id) else { return }
        change(&workspaces[index])
    }

    private mutating func modifyWorkspace(containing pane: Pane.ID, _ change: (inout Workspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.tree.contains(pane) }) else { return }
        change(&workspaces[index])
    }
}
