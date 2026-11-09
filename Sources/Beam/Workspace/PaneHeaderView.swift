import AppKit
import BeamCore

/// The strip along the top of a pane in a split: the pane's title and a
/// close button. Clicking it focuses the pane, double-clicking zooms it, and
/// dragging it moves the pane somewhere else in the workspace.
final class PaneHeaderView: NSView, NSDraggingSource {
    static let height = 24.0
    /// How far the pointer travels before a press becomes a drag.
    private static let dragThreshold = 3.0

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

    private let pane: Pane.ID
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var pressLocation: NSPoint?

    init(pane: Pane.ID, style: GhosttyApp.SplitStyle) {
        self.pane = pane
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

    // A header in an inactive window focuses and drags on the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func close() {
        onClose?()
    }

    // MARK: Clicking and dragging

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        if event.clickCount == 2 {
            onToggleZoom?()
        } else {
            onFocus?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressLocation else { return }
        let location = event.locationInWindow
        guard hypot(location.x - start.x, location.y - start.y) >= Self.dragThreshold else { return }
        pressLocation = nil

        let item = NSPasteboardItem()
        item.setString(pane.description, forType: .beamPane)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: snapshot())
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        pressLocation = nil
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    /// The header as it looks now, for the drag to carry.
    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        return image
    }
}
