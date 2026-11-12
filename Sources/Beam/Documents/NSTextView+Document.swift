import AppKit

// Text views that show a file: Markdown rendered, and plain or rich text.
extension NSTextView {
    /// A read only, selectable TextKit 1 text view that grows with its text,
    /// for a scroll view to hold.
    static func documentTextView() -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.importsGraphics = false
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        // The scroll view draws the background, under the margins too.
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        return view
    }

    /// Replaces the text. `keepingPlace` keeps the line at the top of the
    /// view where it was, or the view at the end when it was there, as for a
    /// log being written.
    func show(_ text: NSAttributedString, keepingPlace: Bool) {
        guard let storage = textStorage else { return }
        guard keepingPlace, storage.length > 0, let place = topPlace() else {
            storage.setAttributedString(text)
            scroll(.zero)
            return
        }
        storage.setAttributedString(text)
        guard storage.length > 0, let layoutManager, let textContainer else { return }
        if place.atEnd {
            layoutManager.ensureLayout(for: textContainer)
            scrollToEndOfDocument(nil)
            return
        }
        let index = min(place.character, storage.length - 1)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: index + 1))
        let line = layoutManager.lineFragmentRect(
            forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil)
        scroll(NSPoint(x: 0, y: line.minY + textContainerOrigin.y + place.offset))
    }

    /// The character starting the line at the top of the view, how far
    /// into that line the view starts, and whether the view is at the end.
    private func topPlace() -> (character: Int, offset: Double, atEnd: Bool)? {
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView else { return nil }
        let visible = scrollView.documentVisibleRect
        let atEnd = visible.minY > 0 && visible.maxY >= bounds.maxY - 1
        let top = NSPoint(x: 0, y: visible.minY - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: top, in: textContainer)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return (layoutManager.characterIndexForGlyph(at: glyph), top.y - line.minY, atEnd)
    }
}
