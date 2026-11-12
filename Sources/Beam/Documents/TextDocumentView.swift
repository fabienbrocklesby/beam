import AppKit

/// A text file, read only and selectable: plain text in SF Mono, rich text
/// as written.
final class TextDocumentView: NSScrollView {
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    let textView = NSTextView.documentTextView()

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 14, height: 12)
        // A long log lays out only as far as it is shown.
        textView.layoutManager?.allowsNonContiguousLayout = true
        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show(_ text: String, keepingPlace: Bool) {
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.show(
            NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: NSColor.textColor]),
            keepingPlace: keepingPlace)
    }

    func show(_ text: NSAttributedString, keepingPlace: Bool) {
        // Rich text is written for a white page; this keeps it readable in
        // dark mode.
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.show(text, keepingPlace: keepingPlace)
    }
}
