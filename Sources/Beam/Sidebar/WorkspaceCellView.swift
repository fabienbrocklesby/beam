import AppKit
import BeamCore

/// A sidebar row: colour tag, folder name with its git branch below, its
/// most urgent agent's state, and a pin or archive mark.
final class WorkspaceCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("WorkspaceCell")

    private let dot = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let branch = NSTextField(labelWithString: "")
    private let agent = NSImageView()
    private let mark = NSImageView()

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        branch.font = .preferredFont(forTextStyle: .subheadline)
        branch.textColor = .secondaryLabelColor
        branch.lineBreakMode = .byTruncatingTail
        branch.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        agent.symbolConfiguration = NSImage.SymbolConfiguration(scale: .medium)
        mark.contentTintColor = .secondaryLabelColor
        mark.symbolConfiguration = NSImage.SymbolConfiguration(scale: .small)
        textField = name
        imageView = dot

        // A hidden branch drops out of the stack, so its row is one line.
        let text = NSStackView(views: [name, branch])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        // The marks sit at the trailing edge however short the name is.
        let stack = NSStackView()
        stack.setViews([dot, text], in: .leading)
        stack.setViews([agent, mark], in: .trailing)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            // The table sizes each row to fit, from these.
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show(_ row: SidebarViewController.Row) {
        dot.image = row.color?.dot
        dot.setAccessibilityElement(row.color != nil)
        name.stringValue = row.name
        name.textColor = row.isArchived ? .secondaryLabelColor : .labelColor
        branch.stringValue = row.branch ?? ""
        branch.isHidden = row.branch == nil
        let symbol = row.isArchived ? "archivebox" : row.isPinned ? "pin.fill" : nil
        mark.image = symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: row.isArchived ? "Archived" : "Pinned")
        }
        mark.isHidden = symbol == nil
        agent.image = row.agent?.image
        agent.toolTip = row.agent?.detail
        agent.isHidden = row.agent == nil
        toolTip = row.folder
    }
}
