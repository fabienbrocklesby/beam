import AppKit
import BeamCore

/// The grab area of one split divider. The visible line is the workspace's
/// background showing between two panes; this view is wider than that line so
/// it is easy to catch, and draws nothing.
final class DividerView: NSView {
    /// How far the grab area reaches past each side of the line.
    private static let grabMargin = 3.0

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

    init(divider: SplitTree.Divider) {
        self.divider = divider
        super.init(frame: Self.grabFrame(for: divider))
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // A divider in an inactive window drags and double-clicks on the first
    // click, rather than spending it on activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: divider.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(divider) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let point = superview.convert(event.locationInWindow, from: nil)
        onDrag?(divider, divider.axis == .horizontal ? point.x : point.y)
    }

    private static func grabFrame(for divider: SplitTree.Divider) -> CGRect {
        switch divider.axis {
        case .horizontal: divider.frame.insetBy(dx: -grabMargin, dy: 0)
        case .vertical: divider.frame.insetBy(dx: 0, dy: -grabMargin)
        }
    }
}
