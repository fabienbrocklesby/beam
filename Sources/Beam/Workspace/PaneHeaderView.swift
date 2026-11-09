import AppKit
import BeamCore

/// The strip along the top of a pane in a split: the pane's title and a
/// close button. Clicking it focuses the pane and double-clicking zooms it.
final class PaneHeaderView: NSView {
    static let height = 24.0

    var title = "" {
        didSet { label.stringValue = title }
    }

    var isFocused = false {
        didSet { label.textColor = isFocused ? .labelColor : .secondaryLabelColor }
    }

    var style: GhosttyApp.SplitStyle {
        didSet { needsDisplay = true }
    }

    var onFocus: (() -> Void)?
    var onToggleZoom: (() -> Void)?
    var onClose: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    init(style: GhosttyApp.SplitStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Pane")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.showsBorderOnlyWhileMouseInside = true
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close Pane"
        closeButton.target = self
        closeButton.action = #selector(close)

        label.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    // The terminal's own background, so the header and the terminal read as
    // one surface.
    override func updateLayer() {
        layer?.backgroundColor = style.background.cgColor
    }

    override func accessibilityLabel() -> String? { title }

    override var mouseDownCanMoveWindow: Bool { false }

    // A header in an inactive window focuses on the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func close() {
        onClose?()
    }

    // MARK: Clicking

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onToggleZoom?()
        } else {
            onFocus?()
        }
    }
}
