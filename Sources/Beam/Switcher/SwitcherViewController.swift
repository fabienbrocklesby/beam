import AppKit
import BeamCore

/// Cmd+P: a search field over every workspace and pane, and what the
/// launcher can open, ranked as the user types. Up and Down move, Return
/// picks, Escape cancels. It reports the pick; the window controller acts
/// on it.
final class SwitcherViewController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource,
    NSTableViewDelegate
{
    struct Item {
        enum Target {
            case workspace(Workspace.ID)
            case pane(Pane.ID)
            case launch(LauncherEntry)
        }

        let target: Target
        /// What the query is matched against.
        let title: String
        let detail: String
        /// An SF Symbol name.
        let symbol: String
    }

    var onPick: ((Item.Target) -> Void)?
    var onCancel: (() -> Void)?

    private static let width = 560.0
    private static let fieldHeight = 48.0
    private static let rowHeight = 32.0
    private static let visibleRows = 9
    private static let listInset = 6.0

    private let items: [Item]
    private var results: [(item: Item, match: FuzzyMatch)] = []
    private let field = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    init(items: [Item]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Frame layout, not constraints: the panel's height follows the result
    /// count while its top edge stays put, which `fitWindow` does by hand.
    override func loadView() {
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldHeight))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let glass = NSImageView(
            image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        glass.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        glass.contentTintColor = .secondaryLabelColor
        glass.frame = NSRect(x: 16, y: 0, width: 22, height: Self.fieldHeight)
        glass.autoresizingMask = [.minYMargin]
        background.addSubview(glass)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = "Go to a workspace or pane, or open an agent"
        field.setAccessibilityLabel("Go to a workspace or pane, or open an agent")
        field.delegate = self
        field.cell?.isScrollable = true
        let fieldLine = field.intrinsicContentSize.height
        field.frame = NSRect(
            x: 46, y: (Self.fieldHeight - fieldLine) / 2, width: Self.width - 46 - 16, height: fieldLine)
        field.autoresizingMask = [.width, .minYMargin]
        background.addSubview(field)

        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = Self.rowHeight
        tableView.backgroundColor = .clear
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Item")))
        // The search field keeps the keyboard; the list follows it.
        tableView.refusesFirstResponder = true
        tableView.target = self
        tableView.action = #selector(pickClickedRow)
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.frame = NSRect(x: 0, y: 0, width: Self.width, height: 0)
        scrollView.autoresizingMask = [.width, .height]
        background.addSubview(scrollView)

        view = background
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        filter()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
    }

    /// The panel's size for `rows` results, before it is first shown.
    static func size(rows: Int) -> NSSize {
        let list = rows == 0 ? 0 : listInset * 2 + rowHeight * Double(min(rows, visibleRows))
        return NSSize(width: width, height: fieldHeight + list)
    }

    private func filter() {
        results = FuzzyMatch.rank(items, by: field.stringValue) { $0.title }
        tableView.reloadData()
        select(0)
        fitWindow()
    }

    private func fitWindow() {
        guard let window = view.window else { return }
        var frame = window.frame
        let height = Self.size(rows: results.count).height
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        window.setFrame(frame, display: true)
        scrollView.frame = NSRect(x: 0, y: 0, width: frame.width, height: height - Self.fieldHeight)
        window.invalidateShadow()
    }

    private func select(_ row: Int) {
        guard results.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func pick(_ row: Int) {
        guard results.indices.contains(row) else { return }
        onPick?(results[row].item.target)
    }

    @objc private func pickClickedRow() {
        pick(tableView.clickedRow)
    }

    // MARK: Search field

    func controlTextDidChange(_ notification: Notification) {
        filter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            select(max(tableView.selectedRow - 1, 0))
        case #selector(NSResponder.moveDown(_:)):
            select(min(tableView.selectedRow + 1, results.count - 1))
        case #selector(NSResponder.insertNewline(_:)):
            pick(tableView.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
        default:
            return false
        }
        return true
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell =
            tableView.makeView(withIdentifier: SwitcherCellView.identifier, owner: nil) as? SwitcherCellView
            ?? SwitcherCellView()
        cell.show(results[row].item, match: results[row].match)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EmphasizedRowView()
    }
}

/// Draws the selection in the accent colour although the list never has the
/// keyboard, as Spotlight does, so the row Return will pick stands out.
private final class EmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}
