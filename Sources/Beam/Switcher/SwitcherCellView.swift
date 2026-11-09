import AppKit
import BeamCore

/// A switcher row: a symbol, the title with the typed letters in bold, and
/// where it lives in secondary text after it.
final class SwitcherCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SwitcherCell")

    private static let font = NSFont.systemFont(ofSize: 14)
    private static let matchFont = NSFont.systemFont(ofSize: 14, weight: .bold)
    /// An attributed title wraps by default, whatever the field's own line
    /// break mode, so it carries its own.
    private static let truncating: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private let symbol = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        // The row's label already says what it is.
        symbol.setAccessibilityElement(false)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultHigh - 1, for: .horizontal)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingHead
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = title
        imageView = symbol

        let stack = NSStackView()
        stack.setViews([symbol, title, detail], in: .leading)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// The detail keeps a readable contrast on the accent-coloured selection.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            detail.textColor =
                backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }

    func show(_ item: SwitcherViewController.Item, match: FuzzyMatch) {
        symbol.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        let matched = Set(match.positions)
        let text = NSMutableAttributedString()
        for (offset, character) in item.title.enumerated() {
            let font = matched.contains(offset) ? Self.matchFont : Self.font
            text.append(
                NSAttributedString(
                    string: String(character), attributes: [.font: font, .paragraphStyle: Self.truncating]))
        }
        title.attributedStringValue = text
        detail.stringValue = item.detail
        setAccessibilityLabel("\(item.title), \(item.detail)")
    }
}
