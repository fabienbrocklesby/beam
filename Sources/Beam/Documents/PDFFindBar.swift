import AppKit

/// The bar over a PDF that Cmd+F shows, laid out as a text view's find bar
/// is: a search field with the match count inside it, buttons for the
/// previous and next match, and Done. Return goes to the next match,
/// Shift+Return the previous, and Escape closes the bar.
final class PDFFindBar: NSView, NSSearchFieldDelegate {
    static let height = 32.0

    var text: String { field.stringValue }

    /// How many matches the search has found, or nil before it finds any.
    /// The match shown is the selection in the PDF, as in a text view.
    var count: Int? {
        didSet { updateCount() }
    }

    var onChange: (() -> Void)?
    /// Called with true for the next match and false for the previous.
    var onStep: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    private let field = FindField()
    private let steps = NSSegmentedControl()
    private let done = NSButton(title: "Done", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        field.placeholderString = "Find in PDF"
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.delegate = self
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        steps.segmentCount = 2
        steps.trackingMode = .momentary
        steps.controlSize = .small
        for (segment, symbol, name) in [(0, "chevron.left", "Previous Match"), (1, "chevron.right", "Next Match")] {
            steps.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: name), forSegment: segment)
            steps.setToolTip(name, forSegment: segment)
            steps.setWidth(24, forSegment: segment)
        }
        steps.target = self
        steps.action = #selector(step(_:))

        done.controlSize = .small
        done.bezelStyle = .push
        done.target = self
        done.action = #selector(close)

        let stack = NSStackView(views: [field, steps, done])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A pane too narrow for the whole bar drops the arrows, then Done,
        // rather than squeezing them: a segmented control squeezed narrower
        // than its segments still draws them, over its neighbours. The field
        // narrows to its minimum before anything drops, as its compression
        // resistance is below the stack's clipping resistance. Return,
        // Shift+Return and Escape do the same jobs.
        stack.setClippingResistancePriority(NSLayoutConstraint.Priority(500), for: .horizontal)
        stack.setVisibilityPriority(.detachOnlyIfNecessary, for: steps)
        stack.setVisibilityPriority(NSStackView.VisibilityPriority(950), for: done)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        updateCount()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Puts keyboard focus in the field with its text selected, so typing
    /// replaces it.
    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
    }

    private func updateCount() {
        field.count = count.map(String.init) ?? ""
        steps.isEnabled = (count ?? 0) > 0
    }

    @objc private func step(_ sender: NSSegmentedControl) {
        onStep?(sender.selectedSegment == 1)
    }

    @objc private func close() {
        onClose?()
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onStep?(NSApp.currentEvent?.modifierFlags.contains(.shift) != true)
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
        default:
            return false
        }
        return true
    }
}

/// A search field that shows the match count inside it, before the clear
/// button, as a text view's find bar does, so a narrow pane narrows the
/// text rather than cutting the count off.
private final class FindField: NSSearchField {
    var count: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            label.isHidden = newValue.isEmpty
            // The field reads `searchTextBounds` again as it lays out, which
            // narrows the text being edited too.
            needsLayout = true
        }
    }

    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isHidden = true
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var searchTextBounds: NSRect {
        var rect = super.searchTextBounds
        if !label.isHidden { rect.size.width -= label.intrinsicContentSize.width + Self.gap }
        return rect
    }

    override func layout() {
        super.layout()
        // The intrinsic size leaves out the padding the label's cell draws
        // with, which Auto Layout adds back but a frame set by hand does not:
        // without it the last digit is cut off.
        let size = label.intrinsicContentSize
        label.frame = label.frame(
            forAlignmentRect: NSRect(
                x: cancelButtonBounds.minX - size.width - Self.gap / 2,
                y: ((bounds.height - size.height) / 2).rounded(),
                width: size.width, height: size.height))
    }

    private static let gap = 4.0
}
