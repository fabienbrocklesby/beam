import AppKit
import BeamCore
import QuickLookThumbnailing
import UniformTypeIdentifiers
import os

/// The strip along the bottom of a pane that shows the files its agent's
/// last reply named, each as a thumbnail and its name. Clicking one shows it
/// in Quick Look, double-clicking opens it in its app, and dragging one
/// carries the file.
final class PreviewTrayView: NSView {
    static let height = 52.0
    /// Most files a tray shows: the first a reply named.
    nonisolated static let limit = 6

    /// Kinds Quick Look shows well. Source code stays out of the tray; a
    /// Cmd+click still opens it.
    nonisolated private static let previewable: [UTType] =
        [.image, .pdf, .html, .movie, .presentation, .spreadsheet]
        + ["com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document", "com.apple.iwork.pages.sffpages"]
        .compactMap { UTType($0) }

    /// Whether `url` gets a thumbnail in the tray. Looks the type up in
    /// Launch Services, so keep it off the main thread.
    nonisolated static func canPreview(_ url: URL) -> Bool {
        guard !FileMention.isTypeScript(url.lastPathComponent),
            let type = UTType(filenameExtension: url.pathExtension)
        else { return false }
        return previewable.contains { type.conforms(to: $0) }
    }

    var files: [URL] = [] {
        didSet {
            guard files != oldValue else { return }
            showChips()
        }
    }

    var style: GhosttyApp.SplitStyle {
        didSet {
            needsDisplay = true
            for chip in chips { chip.style = style }
        }
    }

    /// Called with the index of the file to show in Quick Look.
    var onPreview: ((Int) -> Void)?
    /// Called with the index of the file to open in its app.
    var onOpen: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private let stack = NSStackView()
    private let closeButton = NSButton()
    private var chips: [PreviewChip] { stack.arrangedSubviews.compactMap { $0 as? PreviewChip } }

    init(style: GhosttyApp.SplitStyle) {
        self.style = style
        super.init(frame: .zero)

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Previews")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.showsBorderOnlyWhileMouseInside = true
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close Previews"
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("File Previews")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// The chip showing `files[index]`, which Quick Look zooms from.
    func chip(at index: Int) -> NSView? {
        chips.indices.contains(index) ? chips[index] : nil
    }

    /// The thumbnail of `files[index]`, or its icon until there is one.
    func thumbnail(at index: Int) -> NSImage? {
        chips.indices.contains(index) ? chips[index].thumbnail : nil
    }

    // The header's shade, with a hairline in the divider colour above, so
    // the strip reads as the pane's bottom edge in light and dark.
    override func draw(_ dirtyRect: NSRect) {
        style.headerBackground.setFill()
        bounds.fill()
        style.dividerColor.setFill()
        let hairline = 1 / (window?.backingScaleFactor ?? 2)
        NSRect(x: 0, y: bounds.maxY - hairline, width: bounds.width, height: hairline).fill()
    }

    override var mouseDownCanMoveWindow: Bool { false }

    private func showChips() {
        // Removing a chip cancels its thumbnail and frees it.
        for chip in stack.arrangedSubviews { chip.removeFromSuperview() }
        for (index, url) in files.prefix(Self.limit).enumerated() {
            let chip = PreviewChip(url: url, style: style)
            chip.onClick = { [weak self] in self?.onPreview?(index) }
            chip.onDoubleClick = { [weak self] in self?.onOpen?(index) }
            stack.addArrangedSubview(chip)
        }
    }

    @objc private func close() {
        onClose?()
    }
}

/// One file in the tray: its thumbnail, once Quick Look has made it, and its
/// name.
private final class PreviewChip: NSView, NSDraggingSource {
    private static let thumbnailSide = 32.0
    /// How far the pointer travels before a press becomes a drag.
    private static let dragThreshold = 3.0

    let url: URL
    var style: GhosttyApp.SplitStyle {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var thumbnail: NSImage? { imageView.image }

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var request: QLThumbnailGenerator.Request?
    private var pressLocation: NSPoint?

    init(url: URL, style: GhosttyApp.SplitStyle) {
        self.url = url
        self.style = style
        super.init(frame: .zero)

        // The type's icon until the thumbnail arrives, or for good if Quick
        // Look cannot make one. Looked up by type, so it reads no disk.
        imageView.image = NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = url.lastPathComponent
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 140),
        ])

        toolTip = (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(url.lastPathComponent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    // A tile in the terminal's own background, edged like the drag cards,
    // so it stands off the tray's shade.
    override func draw(_ dirtyRect: NSRect) {
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        style.background.setFill()
        tile.fill()
        NSColor.separatorColor.setStroke()
        tile.stroke()
    }

    // MARK: Thumbnail

    // Made once the chip is on screen, at its window's scale, and cancelled
    // when it leaves, so a closed tray holds no thumbnails.
    override func viewDidMoveToWindow() {
        guard let window else {
            if let request { QLThumbnailGenerator.shared.cancel(request) }
            request = nil
            return
        }
        guard request == nil else { return }
        let size = CGSize(width: Self.thumbnailSide, height: Self.thumbnailSide)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: window.backingScaleFactor, representationTypes: .thumbnail)
        // Framed as Finder frames icons, so a white page still shows on a
        // light tile, and the thumbnail matches the icon it replaces.
        request.iconMode = true
        self.request = request
        // Quick Look calls back on a queue of its own.
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, error in
            guard let image = thumbnail?.cgImage else {
                if let error { Logger.app.debug("no thumbnail: \(error.localizedDescription, privacy: .public)") }
                return
            }
            DispatchQueue.main.async {
                self?.imageView.image = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    // MARK: Clicking and dragging

    override var mouseDownCanMoveWindow: Bool { false }

    // A chip in an inactive window answers the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressLocation else { return }
        let location = event.locationInWindow
        guard hypot(location.x - start.x, location.y - start.y) >= Self.dragThreshold else { return }
        pressLocation = nil

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let frame = imageView.frame
        item.setDraggingFrame(frame, contents: imageView.image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressLocation != nil else { return }
        pressLocation = nil
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
