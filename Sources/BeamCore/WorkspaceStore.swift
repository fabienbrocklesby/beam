import Foundation

/// Every workspace, which one is selected, and the rules for opening,
/// closing and ordering them.
///
/// A workspace with no panes is either pinned (it stays in the sidebar and
/// starts a shell when selected again) or archived (hidden until shown or
/// reopened). An unpinned workspace closes with its last pane.
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
        var workspace = Workspace(folder: (folder as NSString).standardizingPath)
        let taken = Set(workspaces.map(\.name))
        var number = 2
        while taken.contains(workspace.name) {
            workspace.name = "\(workspace.folderName) \(number)"
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

    /// Closes every pane in `id`. Unless pinned, the workspace goes too.
    public mutating func close(_ id: Workspace.ID) {
        guard let index = index(of: id) else { return }
        let sidebarBefore = sidebar
        if workspaces[index].isPinned {
            workspaces[index].empty()
        } else {
            workspaces.remove(at: index)
        }
        moveSelection(awayFrom: id, in: sidebarBefore)
    }

    public mutating func setArchived(_ id: Workspace.ID, _ archived: Bool) {
        guard let index = index(of: id) else { return }
        guard archived else {
            workspaces[index].isArchived = false
            return
        }
        let sidebarBefore = sidebar
        workspaces[index].isArchived = true
        workspaces[index].empty()
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
    /// set, is typed into the pane's shell as it starts.
    @discardableResult
    public mutating func openPane(
        running command: String?, in id: Workspace.ID, folder: String? = nil, bounds: CGRect
    ) -> Pane.ID? {
        guard let index = index(of: id) else { return nil }
        let pane = Pane(workingDirectory: folder ?? workspaces[index].folder, command: command)
        workspaces[index].tree.tile(pane, in: bounds)
        workspaces[index].focusedPane = pane.id
        return pane.id
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
    /// workspace closes with its last pane.
    public mutating func closePane(_ pane: Pane.ID) {
        guard let index = workspaces.firstIndex(where: { $0.tree.contains(pane) }) else { return }
        let neighbour = workspaces[index].tree.remove(pane)
        if workspaces[index].focusedPane == pane {
            workspaces[index].focusedPane = neighbour
        }
        if workspaces[index].tree.isEmpty {
            close(workspaces[index].id)
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
