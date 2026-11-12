import AppKit

/// An image, fitted to the pane and never enlarged past its own size until
/// the user zooms with a pinch, Cmd+= or Cmd+-; Cmd+0 fits it again.
/// Animated GIFs play.
final class ImageDocumentView: NSScrollView {
    /// Takes keyboard focus for the image: a scroll view hands focus to its
    /// document view.
    let imageView: NSImageView = FocusableImageView()
    /// Whether the image follows the pane's size, as it does until the user
    /// zooms.
    private var fits = true

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .underPageBackgroundColor
        allowsMagnification = true
        minMagnification = 0.05
        maxMagnification = 16
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.focusRingType = .none
        documentView = imageView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show(_ image: NSImage) {
        // An image of another size is a new picture, so it is fitted again.
        if image.size != imageView.image?.size { fits = true }
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.size)
        if fits { fit() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if fits { fit() }
    }

    private func fit() {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else { return }
        magnification = min(1, bounds.width / size.width, bounds.height / size.height)
    }

    // MARK: Zooming

    override func magnify(with event: NSEvent) {
        fits = false
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        fits = false
        super.smartMagnify(with: event)
    }

    @objc func zoomIn(_ sender: Any?) {
        zoom(by: 1.25)
    }

    @objc func zoomOut(_ sender: Any?) {
        zoom(by: 0.8)
    }

    @objc func zoomToFit(_ sender: Any?) {
        fits = true
        fit()
    }

    private func zoom(by factor: Double) {
        fits = false
        let visible = documentVisibleRect
        setMagnification(magnification * factor, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
    }
}

/// An image view that takes keyboard focus, which a plain one refuses
/// unless it is editable.
private final class FocusableImageView: NSImageView {
    override var acceptsFirstResponder: Bool { true }
}

/// Keeps an image smaller than the view in its middle rather than its
/// corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
        if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
        return rect
    }
}
