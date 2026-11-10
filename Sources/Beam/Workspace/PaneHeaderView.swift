import AppKit
import BeamCore

/// The strip along the top of a pane in a split: its agent's state, the
/// pane's title and a close button. Clicking it focuses the pane,
/// double-clicking zooms it, and dragging it moves the pane somewhere else in
/// the workspace.
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

    /// What the pane's agent last reported, shown before the title.
    var agent: AgentState? {
        didSet {
            guard agent != oldValue else { return }
            agentMark.image = agent?.image
            agentMark.toolTip = agent?.detail
            agentMark.isHidden = agent == nil
        }
    }

    var style: GhosttyApp.SplitStyle {
        didSet { needsDisplay = true }
    }

    var onFocus: (() -> Void)?
    var onToggleZoom: (() -> Void)?
    var onClose: (() -> Void)?
    /// Called with true as a drag of the pane begins, and false once it ends.
    var onDragging: ((Bool) -> Void)?

    private let pane: Pane.ID
    private let agentMark = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var pressLocation: NSPoint?

    init(pane: Pane.ID, style: GhosttyApp.SplitStyle) {
        self.pane = pane
        self.style = style
        super.init(frame: .zero)

        agentMark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        agentMark.isHidden = true

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

        // A hidden mark drops out of the stack, so the title moves up to the edge.
        let leading = NSStackView(views: [agentMark, label])
        leading.orientation = .horizontal
        leading.spacing = 5
        leading.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leading)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            leading.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -6),
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

    // A shade off the terminal's background, with a hairline in the divider
    // colour below, so the strip reads as the pane's top in light and dark.
    override func draw(_ dirtyRect: NSRect) {
        style.headerBackground.setFill()
        bounds.fill()
        style.dividerColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
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
        // The card starts under the pointer, its symbol where the press was.
        let image = dragImage()
        let press = convert(start, from: nil)
        let origin = NSPoint(x: press.x - Self.cardMargin - 16, y: bounds.midY - image.size.height / 2)
        dragging.setDraggingFrame(NSRect(origin: origin, size: image.size), contents: image)
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

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragging?(true)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragging?(false)
    }

    // MARK: Drag image

    /// Room around the card for its shadow.
    private static let cardMargin = 12.0

    /// A card naming the pane for the drag to carry: its symbol and title on
    /// a rounded tile that floats on a soft shadow.
    private func dragImage() -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let titleWidth = min(ceil((title as NSString).size(withAttributes: [.font: font]).width), 240)
        let card = NSRect(x: Self.cardMargin, y: Self.cardMargin, width: 10 + 14 + 6 + titleWidth + 12, height: 28)
        let size = NSSize(width: card.maxX + Self.cardMargin, height: card.maxY + Self.cardMargin)
        let scale = window?.backingScaleFactor ?? 2
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return NSImage() }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let tile = NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 10
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            shadow.set()
            style.headerBackground.setFill()
            tile.fill()
            NSGraphicsContext.restoreGraphicsState()
            let edge = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 6.5, yRadius: 6.5)
            NSColor.separatorColor.setStroke()
            edge.stroke()

            // At its own size: another configuration would replace the
            // agent image's palette rather than add to it.
            let symbol =
                agent?.image
                ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
            if let icon = symbol {
                let size = icon.size
                icon.draw(
                    in: NSRect(
                        x: card.minX + 17 - size.width / 2, y: card.midY - size.height / 2, width: size.width,
                        height: size.height))
            }

            let truncating = NSMutableParagraphStyle()
            truncating.lineBreakMode = .byTruncatingMiddle
            let text = NSAttributedString(
                string: title,
                attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: truncating])
            let height = ceil(font.ascender - font.descender)
            text.draw(in: NSRect(x: card.minX + 30, y: card.midY - height / 2, width: titleWidth, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}
