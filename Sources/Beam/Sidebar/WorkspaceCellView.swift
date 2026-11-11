import AppKit
import BeamCore

/// A sidebar row: colour tag, workspace name with its git branch below, and
/// its most urgent agent's state. Its section says whether it is pinned or
/// archived.
final class WorkspaceCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("WorkspaceCell")

    /// An edit of the name in place.
    private struct Rename {
        let original: String
        let onKey: () -> Void
        let onEnd: (String) -> Void
    }

    private let dot = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let branch = NSTextField(labelWithString: "")
    private let agent = NSImageView()
    private var rename: Rename?

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
        textField = name
        imageView = dot

        // A hidden branch drops out of the stack, so its row is one line.
        let text = NSStackView(views: [name, branch])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        // The mark sits at the trailing edge however short the name is.
        let stack = NSStackView()
        stack.setViews([dot, text], in: .leading)
        stack.setViews([agent], in: .trailing)
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
        agent.image = row.agent?.image
        agent.toolTip = row.agent?.detail
        agent.isHidden = row.agent == nil
        toolTip = row.folder
    }

    /// Edits the name in place, as Finder renames a file, and says whether
    /// it could. Return and Escape run `onKey`, which takes the keyboard
    /// away and so ends the edit; Escape first puts the old name back. A
    /// click elsewhere ends it too. However it ends, `onEnd` gets the name.
    func beginRename(onKey: @escaping () -> Void, onEnd: @escaping (String) -> Void) -> Bool {
        name.isEditable = true
        name.delegate = self
        guard window?.makeFirstResponder(name) == true else {
            name.isEditable = false
            return false
        }
        rename = Rename(original: name.stringValue, onKey: onKey, onEnd: onEnd)
        return true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let rename else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            textView.string = rename.original
        case #selector(NSResponder.insertNewline(_:)):
            break
        default:
            return false
        }
        rename.onKey()
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let rename else { return }
        self.rename = nil
        name.isEditable = false
        rename.onEnd(name.stringValue)
    }
}
