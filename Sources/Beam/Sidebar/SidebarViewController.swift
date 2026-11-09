import AppKit
import BeamCore

/// The workspace list. Shows what it is given and reports what the user asks
/// for; the window controller owns the store and decides.
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    enum Command {
        case select
        case setPinned(Bool)
        case setColor(Workspace.Color?)
        case setArchived(Bool)
        case close
        /// Moves the workspace to the gap above this row, as dropped.
        case move(to: Int)
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

    var onCommand: ((Command, Workspace.ID) -> Void)?

    private let tableView = NSTableView()
    private var rows: [Row] = []
    /// Set while `show` changes the table, whose own selection changes then
    /// are not the user's.
    private var isShowing = false

    override func loadView() {
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Workspace")))
        tableView.allowsEmptySelection = false
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
        isShowing = true
        defer { isShowing = false }
        let rows = workspaces.map { Row($0, branch: branches[$0.id], agent: agents[$0.id]) }
        if rows != self.rows {
            self.rows = rows
            tableView.reloadData()
        }
        let selected = rows.firstIndex { $0.id == selection }.map { IndexSet(integer: $0) } ?? IndexSet()
        if tableView.selectedRowIndexes != selected {
            tableView.selectRowIndexes(selected, byExtendingSelection: false)
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell =
            tableView.makeView(withIdentifier: WorkspaceCellView.identifier, owner: nil) as? WorkspaceCellView
            ?? WorkspaceCellView()
        cell.show(rows[row])
        return cell
    }

    // MARK: Dragging rows

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard rows.indices.contains(row), !rows[row].isArchived else { return nil }
        let item = NSPasteboardItem()
        item.setString(rows[row].id.description, forType: .beamWorkspace)
        return item
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        // Archived rows come last and stay there, so a drop lands above them.
        let movable = rows.count { !$0.isArchived }
        guard row <= movable else { return [] }
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let id = info.draggingPasteboard.string(forType: .beamWorkspace)
                .flatMap(UUID.init(uuidString:)).map({ Workspace.ID(uuid: $0) })
        else { return false }
        onCommand?(.move(to: row), id)
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard !isShowing, rows.indices.contains(row) else { return }
        onCommand?(.select, rows[row].id)
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard rows.indices.contains(tableView.clickedRow) else { return }
        let row = rows[tableView.clickedRow]

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
}
