import AppKit
import BeamCore

/// Lays a `MarkdownDocument` out as TextKit 1 text for `MarkdownView`:
/// system font prose, SF Mono code on a quiet fill, quotes and tables as
/// text blocks. Every colour is a dynamic system colour, so the text follows
/// light and dark without being rendered again.
enum MarkdownRenderer {
    /// Marks a heading's text with its anchor, the slug a `#` link names.
    static let anchor = NSAttributedString.Key("BeamMarkdownAnchor")

    private static let bodySize = 14.0
    private static let codeSize = 12.5
    private static let tableSize = 13.0
    /// Space after a block at the top level.
    private static let blockSpacing = 12.0
    /// Space after each paragraph in a list.
    private static let listSpacing = 4.0

    /// Where a block sits: inside which quotes, how far into a list, and in
    /// what colour its text runs.
    private struct Context {
        var quotes: [NSTextBlock] = []
        var indent = 0.0
        var color = NSColor.labelColor
        /// Space after each block.
        var spacing = MarkdownRenderer.blockSpacing
    }

    static func render(_ document: MarkdownDocument) -> NSAttributedString {
        let output = NSMutableAttributedString()
        append(document.blocks, to: output, in: Context())
        // The last block's newline would only pad the bottom.
        if output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
        return output
    }

    // MARK: Blocks

    private static func append(
        _ blocks: [MarkdownDocument.Block], to output: NSMutableAttributedString, in context: Context
    ) {
        for block in blocks {
            switch block {
            case .heading(let level, let text):
                appendHeading(level: level, text, to: output, in: context)
            case .paragraph(let text):
                let style = paragraphStyle(in: context)
                output.append(inline(text, font: .systemFont(ofSize: bodySize), color: context.color, style: style))
                output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            case .code(_, let code):
                appendCode(code, to: output, in: context)
            case .quote(let blocks):
                appendQuote(blocks, to: output, in: context)
            case .list(let list):
                appendList(list, to: output, in: context)
            case .table(let table):
                appendTable(table, to: output, in: context)
            case .rule:
                let rule = textBlock(in: context, after: context.spacing + 4)
                rule.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                rule.setBorderColor(.separatorColor, for: .minY)
                rule.setWidth(8, type: .absoluteValueType, for: .margin, edge: .minY)
                let style = paragraphStyle(in: context, blocks: [rule])
                // An empty line takes its font's height, so the font is tiny.
                output.append(
                    NSAttributedString(
                        string: "\n", attributes: [.paragraphStyle: style, .font: NSFont.systemFont(ofSize: 1)]))
            }
        }
    }

    private static func appendHeading(
        level: Int, _ text: AttributedString, to output: NSMutableAttributedString, in context: Context
    ) {
        let (size, weight, before, after): (Double, NSFont.Weight, Double, Double) =
            switch level {
            case 1: (26, .bold, 24, 14)
            case 2: (20, .bold, 22, 12)
            case 3: (17, .semibold, 18, 8)
            case 4: (15, .semibold, 14, 6)
            default: (bodySize, .semibold, 12, 6)
            }
        let style: NSMutableParagraphStyle
        if level <= 2 {
            // The two top levels get a hairline below, as most renderers draw.
            let underline = textBlock(in: context, after: after)
            underline.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
            underline.setBorderColor(.separatorColor, for: .maxY)
            underline.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxY)
            style = paragraphStyle(in: context, blocks: [underline])
        } else {
            style = paragraphStyle(in: context)
            style.paragraphSpacing = after
        }
        style.paragraphSpacingBefore = output.length == 0 ? 0 : before
        let color = level >= 6 ? NSColor.secondaryLabelColor : context.color
        let heading = NSMutableAttributedString(
            attributedString: inline(text, font: .systemFont(ofSize: size, weight: weight), color: color, style: style))
        heading.addAttribute(
            anchor, value: slug(String(text.characters)), range: NSRange(location: 0, length: heading.length))
        output.append(heading)
        output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
    }

    private static func appendCode(_ code: String, to output: NSMutableAttributedString, in context: Context) {
        let fill = NSTextBlock()
        fill.setValue(100, type: .percentageValueType, for: .width)
        fill.backgroundColor = .quaternarySystemFill
        fill.setWidth(12, type: .absoluteValueType, for: .padding)
        // The last line's descent and spacing already pad the bottom.
        fill.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
        let style = paragraphStyle(in: context, blocks: [textBlock(in: context, after: context.spacing), fill])
        style.lineSpacing = 2
        // One paragraph per line, so a blank line keeps its height.
        output.append(
            NSAttributedString(
                string: code + "\n",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular),
                    .foregroundColor: NSColor.labelColor, .paragraphStyle: style,
                ]))
    }

    private static func appendQuote(
        _ blocks: [MarkdownDocument.Block], to output: NSMutableAttributedString, in context: Context
    ) {
        let bar = textBlock(in: context, after: context.spacing)
        bar.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        bar.setBorderColor(.quaternaryLabelColor, for: .minX)
        bar.setWidth(14, type: .absoluteValueType, for: .padding, edge: .minX)
        var inner = context
        inner.quotes.append(bar)
        inner.indent = 0
        inner.color = .secondaryLabelColor
        let quote = NSMutableAttributedString()
        append(blocks, to: quote, in: inner)
        // The quote's own margin spaces it from what follows, so its bar
        // ends with its text.
        setSpacing(0, ofLastParagraphIn: quote)
        output.append(quote)
    }

    /// A block indented to the context's list level, with `after` below it.
    /// A block's background covers its margins, so a filled block goes
    /// inside one of these.
    private static func textBlock(in context: Context, after: Double) -> NSTextBlock {
        let block = NSTextBlock()
        // Without a width a block is as narrow as a character. A full one
        // fits its margins and padding inside the column.
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        block.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
        return block
    }

    // MARK: Lists

    private static func appendList(
        _ list: MarkdownDocument.List, to output: NSMutableAttributedString, in context: Context
    ) {
        let font = NSFont.systemFont(ofSize: bodySize)
        let widest = "\(list.items.map(\.ordinal).max() ?? 1)." as NSString
        let markerWidth = list.isOrdered ? max(24, ceil(widest.size(withAttributes: [.font: font]).width) + 10) : 22
        var inner = context
        inner.indent += markerWidth
        inner.spacing = listSpacing
        let bullet = ["•", "◦", "▪"][Int(context.indent / 22) % 3]
        for item in list.items {
            let text = NSMutableAttributedString()
            append(item.blocks, to: text, in: inner)
            let marker =
                item.checked.map { checkbox($0, font: font) }
                ?? NSAttributedString(
                    string: list.isOrdered ? "\(item.ordinal)." : bullet,
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
            addMarker(marker, to: text, indent: context.indent, textIndent: inner.indent, font: font)
            output.append(text)
        }
        // Inside a list item the item's own spacing follows.
        if context.spacing != listSpacing { setSpacing(context.spacing, ofLastParagraphIn: output) }
    }

    /// Puts `marker` before an item's first line, right aligned in the space
    /// before its text, when the item starts with a paragraph.
    private static func addMarker(
        _ marker: NSAttributedString, to item: NSMutableAttributedString, indent: Double, textIndent: Double,
        font: NSFont
    ) {
        guard item.length > 0,
            let style = (item.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle,
            style.firstLineHeadIndent == textIndent
        else { return }
        style.firstLineHeadIndent = indent
        style.tabStops = [
            NSTextTab(textAlignment: .right, location: textIndent - 8),
            NSTextTab(textAlignment: .left, location: textIndent),
        ]
        let paragraph = (item.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        item.addAttribute(.paragraphStyle, value: style, range: paragraph)
        let lead = NSMutableAttributedString(string: "\t", attributes: [.font: font])
        lead.append(marker)
        lead.append(NSAttributedString(string: "\t", attributes: [.font: font]))
        lead.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: lead.length))
        item.insert(lead, at: 0)
    }

    private static func checkbox(_ checked: Bool, font: NSFont) -> NSAttributedString {
        let color: NSColor = checked ? .controlAccentColor : .tertiaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [checked ? .white : color, color]))
        guard
            let image = NSImage(
                systemSymbolName: checked ? "checkmark.square.fill" : "square",
                accessibilityDescription: checked ? "Done" : "To do")?
                .withSymbolConfiguration(configuration)
        else {
            return NSAttributedString(string: checked ? "☑" : "☐", attributes: [.font: font])
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centred on the text's lowercase letters.
        attachment.bounds = NSRect(
            x: 0, y: (font.xHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    /// Sets the space after `text`'s last paragraph, unless that paragraph
    /// ends a block, whose margin spaces it.
    private static func setSpacing(_ spacing: Double, ofLastParagraphIn text: NSMutableAttributedString) {
        guard text.length > 0 else { return }
        let paragraph = (text.string as NSString).paragraphRange(for: NSRange(location: text.length - 1, length: 0))
        guard
            let style =
                (text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle,
            style.paragraphSpacing > 0
        else { return }
        style.paragraphSpacing = spacing
        text.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    // MARK: Tables

    /// A table whose columns take the width their text needs, shrinking
    /// together when the view is narrower. `NSTextTable`'s automatic layout
    /// would make every column the same width.
    private static func appendTable(
        _ table: MarkdownDocument.Table, to output: NSMutableAttributedString, in context: Context
    ) {
        let rows = (table.header.isEmpty ? [] : [table.header]) + table.rows
        let columns = max(table.alignments.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return }
        let font = NSFont.systemFont(ofSize: tableSize)
        let bold = NSFont.systemFont(ofSize: tableSize, weight: .semibold)
        let padding = 10.0

        let cells = rows.enumerated().map { row, cells in
            (0..<columns).map { column in
                inline(
                    column < cells.count ? cells[column] : AttributedString(),
                    font: row == 0 && !table.header.isEmpty ? bold : font, color: .labelColor, style: nil)
            }
        }
        // Measured on one line and capped, so a long cell wraps rather than
        // starving its neighbours.
        let widths = (0..<columns).map { column in
            min(max(cells.map { ceil($0[column].size().width) }.max() ?? 0, 24), 360) + 2 * padding + 1
        }
        let total = widths.reduce(0, +)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.layoutAlgorithm = .fixedLayoutAlgorithm
        textTable.hidesEmptyCells = false
        textTable.setValue(total, type: .absoluteValueType, for: .width)
        textTable.setValue(100, type: .percentageValueType, for: .maximumWidth)
        // A table's own margins are ignored.
        let spacer = textBlock(in: context, after: context.spacing)

        for (row, line) in cells.enumerated() {
            for (column, text) in line.enumerated() {
                let cell = NSTextTableBlock(
                    table: textTable, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setValue(widths[column] / total * 100, type: .percentageValueType, for: .width)
                cell.setWidth(padding, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(padding, type: .absoluteValueType, for: .padding, edge: .maxX)
                cell.setWidth(5, type: .absoluteValueType, for: .padding, edge: .minY)
                cell.setWidth(5, type: .absoluteValueType, for: .padding, edge: .maxY)
                // Each line drawn once, as collapsed borders would, which
                // trap AppKit while drawing a table inside another block.
                cell.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxX)
                cell.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
                if row == 0 { cell.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY) }
                if column == 0 { cell.setWidth(1, type: .absoluteValueType, for: .border, edge: .minX) }
                cell.setBorderColor(.separatorColor)
                if row == 0, !table.header.isEmpty { cell.backgroundColor = .quaternarySystemFill }
                let style = NSMutableParagraphStyle()
                style.textBlocks = context.quotes + [spacer, cell]
                style.lineSpacing = 2
                style.alignment =
                    switch column < table.alignments.count ? table.alignments[column] : .left {
                    case .left: .natural
                    case .center: .center
                    case .right: .right
                    }
                let paragraph = NSMutableAttributedString(attributedString: text)
                paragraph.append(NSAttributedString(string: "\n", attributes: [.font: font]))
                paragraph.addAttribute(
                    .paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))
                output.append(paragraph)
            }
        }
    }

    // MARK: Inline text

    /// A paragraph's style in `context`, inside `blocks` when it has any,
    /// whose margins then space it from what follows.
    private static func paragraphStyle(in context: Context, blocks: [NSTextBlock] = []) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.textBlocks = context.quotes + blocks
        style.firstLineHeadIndent = blocks.isEmpty ? context.indent : 0
        style.headIndent = blocks.isEmpty ? context.indent : 0
        style.paragraphSpacing = blocks.isEmpty ? context.spacing : 0
        style.lineSpacing = 3
        return style
    }

    /// `text` in `font`, with its emphasis, code, links and breaks.
    private static func inline(
        _ text: AttributedString, font: NSFont, color: NSColor, style: NSParagraphStyle?
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for run in text.runs {
            var string = String(text[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if let style { attributes[.paragraphStyle] = style }

            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if intent.contains(.code) {
                attributes[.font] = NSFont.monospacedSystemFont(
                    ofSize: font.pointSize * 0.88, weight: traits.contains(.bold) ? .semibold : .regular)
                attributes[.backgroundColor] = NSColor.quaternarySystemFill
            } else if traits.isEmpty {
                attributes[.font] = font
            } else {
                let descriptor = font.fontDescriptor.withSymbolicTraits(
                    font.fontDescriptor.symbolicTraits.union(traits))
                attributes[.font] = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if intent.contains(.softBreak) {
                string = " "
            } else if intent.contains(.lineBreak) {
                string = "\u{2028}"
            }
            if let url = run.link {
                attributes[.link] = url.absoluteURL
            } else if let url = run.imageURL {
                // Images are not drawn inline yet, so the alt text links to
                // the image.
                attributes[.link] = url.absoluteURL
                if string.isEmpty { string = url.lastPathComponent }
            }
            output.append(NSAttributedString(string: string, attributes: attributes))
        }
        return output
    }

    /// A heading's anchor as GitHub writes it: lower case, punctuation
    /// dropped, spaces as hyphens.
    static func slug(_ heading: String) -> String {
        String(
            heading.lowercased().compactMap { character in
                if character == " " { return "-" }
                return character.isLetter || character.isNumber || character == "-" || character == "_"
                    ? character : nil
            })
    }
}
