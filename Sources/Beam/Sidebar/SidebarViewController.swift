import AppKit
import BeamCore

/// The workspace list, in sections: Pinned, the rest under Workspaces, and
/// Archived while shown. Shows what it is given and reports what the user
/// asks for; the window controller owns the store and decides.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    enum Command {
        case select
        case setPinned(Bool)
        case setColor(Workspace.Color?)
        case setArchived(Bool)
        case close
        /// Moves the workspace into the pinned or unpinned section, to the gap
        /// above this row of it, as dropped.
        case move(pinned: Bool, to: Int)
        /// Renames the workspace to what was typed into its row.
        case rename(String)
    }

    /// What a row shows, so the table reloads only when that changes.
    struct Row: Equatable {
        let id: Workspace.ID
        let name: String
        let folder: String
        let branch: String?
        /// The state of its most urgent agent.
        let agent: AgentState?
        let color: Workspace.Color?
        let isPinned: Bool
        let isArchived: Bool

        init(_ workspace: Workspace, branch: String?, agent: AgentState?) {
            id = workspace.id
            name = workspace.name
            folder = workspace.folder
            self.branch = branch
            self.agent = agent
            color = workspace.color
            isPinned = workspace.isPinned
            isArchived = workspace.isArchived
        }
    }

    private struct MenuCommand {
        let command: Command
        let workspace: Workspace.ID
    }

    private enum Section {
        case pinned
        case workspaces
        case archived

        var title: String {
            switch self {
            case .pinned: "Pinned"
            case .workspaces: "Workspaces"
            case .archived: "Archived"
            }
        }
    }

    /// A line of the table: a section's header, or a workspace.
    private enum Item: Equatable {
        case header(Section)
        case row(Row)
    }

    var onCommand: ((Command, Workspace.ID) -> Void)?
    /// The Workspaces header's add button was clicked.
    var onNewWorkspace: (() -> Void)?
    /// Return or Escape in a row being renamed: the keyboard goes back to
    /// the terminal, which ends the edit.
    var onFinishRename: (() -> Void)?

    private let tableView = NSTableView()
    private var items: [Item] = []
    /// Set while `show` changes the table, whose own selection changes then
    /// are not the user's.
    private var isShowing = false
    /// The workspace whose row is being renamed. Reloading the table would
    /// end the edit, so what `show` is given meanwhile waits in
    /// `shownWhileRenaming` until it ends.
    private var renaming: Workspace.ID?
    private var shownWhileRenaming: (() -> Void)?

    override func loadView() {
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Workspace")))
        tableView.allowsEmptySelection = false
        tableView.floatsGroupRows = false
        // Rows with a git branch take a second line.
        tableView.usesAutomaticRowHeights = true
        // Picking a workspace puts the keyboard in its terminal, not the list.
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Workspaces")
        // Rows drag to a new place, the others parting to show where.
        tableView.registerForDraggedTypes([.beamWorkspace])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .gap

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        view = scrollView
    }

    func show(
        _ workspaces: [Workspace], branches: [Workspace.ID: String], agents: [Workspace.ID: AgentState],
        selection: Workspace.ID?
    ) {
        guard renaming == nil else {
            shownWhileRenaming = { [weak self] in
                self?.show(workspaces, branches: branches, agents: agents, selection: selection)
            }
            return
        }
        isShowing = true
        defer { isShowing = false }
        let rows = workspaces.map { Row($0, branch: branches[$0.id], agent: agents[$0.id]) }
        let pinned = rows.filter { $0.isPinned && !$0.isArchived }
        let archived = rows.filter(\.isArchived)
        // Workspaces always shows, as the home of the add button and a place
        // to drop a workspace to unpin it.
        var items = pinned.isEmpty ? [] : [.header(.pinned)] + pinned.map(Item.row)
        items += [.header(.workspaces)] + rows.filter { !$0.isPinned && !$0.isArchived }.map(Item.row)
        if !archived.isEmpty { items += [.header(.archived)] + archived.map(Item.row) }
        if items != self.items {
            self.items = items
            tableView.reloadData()
        }
        let selected = items.indices.first { row(at: $0)?.id == selection }.map { IndexSet(integer: $0) } ?? IndexSet()
        if tableView.selectedRowIndexes != selected {
            tableView.selectRowIndexes(selected, byExtendingSelection: false)
        }
    }

    /// The workspace on table row `index`, or nil for a header.
    private func row(at index: Int) -> Row? {
        guard items.indices.contains(index), case .row(let row) = items[index] else { return nil }
        return row
    }

    @objc private func newWorkspace() {
        onNewWorkspace?()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch items[row] {
        case .header(let section):
            let cell =
                tableView.makeView(withIdentifier: SidebarHeaderCellView.identifier, owner: nil)
                as? SidebarHeaderCellView ?? SidebarHeaderCellView()
            cell.show(section.title, add: section == .workspaces ? (self, #selector(newWorkspace)) : nil)
            return cell
        case .row(let workspace):
            let cell =
                tableView.makeView(withIdentifier: WorkspaceCellView.identifier, owner: nil) as? WorkspaceCellView
                ?? WorkspaceCellView()
            cell.show(workspace)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        self.row(at: row) == nil
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        self.row(at: row) != nil
    }

    // MARK: Dragging rows

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard let workspace = self.row(at: row), !workspace.isArchived else { return nil }
        let item = NSPasteboardItem()
        item.setString(workspace.id.description, forType: .beamWorkspace)
        return item
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        // Above the first header is the start of the first section.
        let target = max(row, 1)
        guard destination(above: target) != nil else { return [] }
        if target != row || dropOperation == .on { tableView.setDropRow(target, dropOperation: .above) }
        return .move
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let id = info.draggingPasteboard.string(forType: .beamWorkspace)
                .flatMap(UUID.init(uuidString:)).map({ Workspace.ID(uuid: $0) }),
            let (pinned, position) = destination(above: row)
        else { return false }
        onCommand?(.move(pinned: pinned, to: position), id)
        return true
    }

    /// Where a drop in the gap above table row `row` lands: whether its
    /// section is the pinned one, and the position among that section's
    /// rows. The gap above a header ends the section before it. Nothing
    /// lands among the archived rows.
    private func destination(above row: Int) -> (pinned: Bool, position: Int)? {
        var position = 0
        for item in items[..<min(row, items.count)].reversed() {
            switch item {
            case .row: position += 1
            case .header(.pinned): return (true, position)
            case .header(.workspaces): return (false, position)
            case .header(.archived): return nil
            }
        }
        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isShowing, let workspace = row(at: tableView.selectedRow) else { return }
        onCommand?(.select, workspace.id)
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let row = row(at: tableView.clickedRow) else { return }

        let rename = NSMenuItem(title: "Rename", action: #selector(renameWorkspace(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = row.id
        menu.addItem(rename)
        menu.addItem(.separator())
        menu.addItem(item(row.isPinned ? "Unpin" : "Pin", .setPinned(!row.isPinned), row))

        let colors = NSMenu()
        let none = item("None", .setColor(nil), row)
        none.state = row.color == nil ? .on : .off
        colors.addItem(none)
        colors.addItem(.separator())
        for color in Workspace.Color.allCases {
            let colorItem = item(color.title, .setColor(color), row)
            colorItem.image = color.dot
            colorItem.state = row.color == color ? .on : .off
            colors.addItem(colorItem)
        }
        let colorsItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorsItem.submenu = colors
        menu.addItem(colorsItem)

        menu.addItem(item(row.isArchived ? "Unarchive" : "Archive", .setArchived(!row.isArchived), row))
        menu.addItem(.separator())
        menu.addItem(item("Close Workspace", .close, row))
    }

    private func item(_ title: String, _ command: Command, _ row: Row) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = MenuCommand(command: command, workspace: row.id)
        return item
    }

    @objc private func runMenuCommand(_ sender: NSMenuItem) {
        guard let menuCommand = sender.representedObject as? MenuCommand else { return }
        onCommand?(menuCommand.command, menuCommand.workspace)
    }

    /// Edits the name in the item's workspace's row.
    @objc private func renameWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Workspace.ID,
            let index = items.indices.first(where: { row(at: $0)?.id == id })
        else { return }
        tableView.scrollRowToVisible(index)
        guard let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: true) as? WorkspaceCellView
        else { return }
        let onKey = { [weak self] in
            guard let self else { return }
            onFinishRename?()
            // Ending the edit drops the bold the table gives a selected
            // row's name, and only reloading the row once the edit is over
            // puts it back.
            guard renaming == nil, let index = items.indices.first(where: { row(at: $0)?.id == id }) else { return }
            tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
        }
        let began = cell.beginRename(onKey: onKey) { [weak self] name in
            guard let self else { return }
            renaming = nil
            let show = shownWhileRenaming
            shownWhileRenaming = nil
            show?()
            onCommand?(.rename(name), id)
        }
        if began { renaming = id }
    }
}
