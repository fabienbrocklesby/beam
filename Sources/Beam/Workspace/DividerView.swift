import AppKit
import BeamCore

/// The grab area of one split divider. The visible line is the workspace's
/// background showing between two panes; this view is wider than that line so
/// it is easy to catch, and draws only a highlight over it while the pointer
/// is on it or dragging it.
final class DividerView: NSView {
    /// How far the grab area reaches past each side of the line.
    private static let grabMargin = 3.0
    /// How far the highlight reaches past each side of the line.
    private static let highlightMargin = 1.0
    /// How long the pointer rests on the divider before it lights up, so
    /// one passing over it on the way somewhere else does not flash it.
    private static let hoverDelay = 0.2

    var divider: SplitTree.Divider {
        didSet {
            guard divider != oldValue else { return }
            frame = Self.grabFrame(for: divider)
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Reports where the user dragged the divider's centre, in the
    /// superview's coordinates along the divider's axis.
    var onDrag: ((SplitTree.Divider, Double) -> Void)?
    var onDoubleClick: ((SplitTree.Divider) -> Void)?

    /// A layer of its own, so it fades in and out by Core Animation.
    private let highlight = CALayer()
    private var isHovered = false {
        didSet { updateHighlight() }
    }
    private var isDragging = false {
        didSet { updateHighlight() }
    }

    init(divider: SplitTree.Divider) {
        self.divider = divider
        super.init(frame: Self.grabFrame(for: divider))
        wantsLayer = true
        highlight.opacity = 0
        // It follows the divider at once while dragged, and fades only as
        // `updateHighlight` says.
        highlight.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull()]
        layer?.addSublayer(highlight)
        layOutHighlight()
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag],
                owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    // Runs with this view's appearance current, so the accent colour resolves
    // for light or dark mode.
    override func updateLayer() {
        highlight.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    // Not called for the frame `init(frame:)` sets, hence the call there too.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layOutHighlight()
    }

    private func layOutHighlight() {
        let inset = Self.grabMargin - Self.highlightMargin
        highlight.frame =
            switch divider.axis {
            case .horizontal: bounds.insetBy(dx: inset, dy: 0)
            case .vertical: bounds.insetBy(dx: 0, dy: inset)
            }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // A divider in an inactive window drags and double-clicks on the first
    // click, rather than spending it on activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: divider.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        if event.clickCount == 2 { onDoubleClick?(divider) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        onDrag?(divider, divider.axis == .horizontal ? point.x : point.y)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    /// Lights the divider at once for a drag, and after `hoverDelay` for a
    /// pointer resting on it: the animation holds its starting opacity that
    /// long before it fades.
    private func updateHighlight() {
        let opacity: Float = isHovered || isDragging ? 1 : 0
        let current = highlight.presentation()?.opacity ?? highlight.opacity
        let rest = opacity == 1 && !isDragging ? Self.hoverDelay : 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [current, current, opacity]
        fade.keyTimes = [0, NSNumber(value: rest / (rest + 0.15)), 1]
        fade.duration = rest + 0.15
        highlight.opacity = opacity
        highlight.add(fade, forKey: "fade")
    }

    private static func grabFrame(for divider: SplitTree.Divider) -> CGRect {
        switch divider.axis {
        case .horizontal: divider.frame.insetBy(dx: -grabMargin, dy: 0)
        case .vertical: divider.frame.insetBy(dx: 0, dy: -grabMargin)
        }
    }
}
