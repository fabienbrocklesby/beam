import AppKit

/// A section header in the sidebar, such as Pinned or Workspaces, with an
/// add button at its trailing end when the section takes new workspaces.
final class SidebarHeaderCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarHeaderCell")

    private let title = NSTextField(labelWithString: "")
    private let addButton = NSButton()

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.lineBreakMode = .byTruncatingTail
        textField = title

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Workspace")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        addButton.bezelStyle = .accessoryBarAction
        addButton.showsBorderOnlyWhileMouseInside = true
        addButton.contentTintColor = .secondaryLabelColor
        addButton.toolTip = "New Workspace…"

        title.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        addSubview(addButton)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            title.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 20),
            addButton.heightAnchor.constraint(equalToConstant: 20),
            // The table sizes each row to fit, from these.
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Shows `text`, with the add button when `add` is given to run.
    func show(_ text: String, add: (target: AnyObject, action: Selector)?) {
        title.stringValue = text
        addButton.isHidden = add == nil
        addButton.target = add?.target
        addButton.action = add?.action
    }
}
