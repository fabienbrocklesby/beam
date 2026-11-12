import AppKit
import BeamCore

/// A rendered Markdown file: read only, selectable, in a readable column
/// centred in the pane.
///
/// Built on TextKit 1: TextKit 2 lays every table cell out as a paragraph of
/// its own, without a word, and never falls back by itself.
final class MarkdownView: NSScrollView, NSTextViewDelegate {
    /// The widest the text column grows, about 90 characters of body text.
    private static let columnWidth = 700.0
    private static let minimumMargin = 28.0

    /// Called with a file a link names.
    var onOpenFile: ((URL) -> Void)?

    let textView = NSTextView.documentTextView()
    private var fileURL: URL?

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textView.delegate = self
        textView.textContainerInset = NSSize(width: Self.minimumMargin, height: 24)
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Shows `document`, the file at `url`, keeping the line at the top
    /// when it is the same file again.
    func show(_ document: MarkdownDocument, of url: URL) {
        let isReload = fileURL == url
        fileURL = url
        textView.show(MarkdownRenderer.render(document), keepingPlace: isReload)
    }

    // The column stays centred and readable as the pane resizes.
    override func tile() {
        super.tile()
        let width = contentView.bounds.width
        let margin = max(Self.minimumMargin, ((width - Self.columnWidth) / 2).rounded(.down))
        if textView.textContainerInset.width != margin {
            textView.textContainerInset.width = margin
        }
    }

    // MARK: NSTextViewDelegate

    /// Web links go to the browser, a link to a heading in this file
    /// scrolls to it, and a link to another file opens it.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        guard url.isFileURL else {
            NSWorkspace.shared.open(url)
            return true
        }
        if url.path == fileURL?.path {
            if let fragment = url.fragment { scroll(toAnchor: fragment) }
            return true
        }
        onOpenFile?(url)
        return true
    }

    private func scroll(toAnchor fragment: String) {
        guard let storage = textView.textStorage else { return }
        let wanted = MarkdownRenderer.slug(fragment.removingPercentEncoding ?? fragment)
        var found: NSRange?
        storage.enumerateAttribute(MarkdownRenderer.anchor, in: NSRange(location: 0, length: storage.length)) {
            value, range, stop in
            guard value as? String == wanted else { return }
            found = range
            stop.pointee = true
        }
        guard let found, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: found, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let origin = textView.textContainerOrigin
        textView.scroll(NSPoint(x: 0, y: rect.minY + origin.y - 12))
    }
}
