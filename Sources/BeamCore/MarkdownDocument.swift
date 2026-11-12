import Foundation

/// A Markdown file as blocks Beam lays out itself, from Foundation's parser.
///
/// `AttributedString(markdown:)` records each run's place in the block
/// structure (`presentationIntent`) but nothing lays that out, so it becomes
/// this tree. The parser also misses some of what agents write, which is
/// handled here: YAML front matter becomes a code block, `[ ]` and `[x]`
/// starting a list item become a checkbox, and HTML shows as its text.
/// Footnotes and math stay as written. Inline text keeps the parser's
/// emphasis, code, strikethrough, link and image attributes.
public struct MarkdownDocument: Equatable, Sendable {
    public indirect enum Block: Equatable, Sendable {
        case heading(level: Int, AttributedString)
        case paragraph(AttributedString)
        case code(language: String?, String)
        case quote([Block])
        case list(List)
        case table(Table)
        case rule
    }

    public struct List: Equatable, Sendable {
        public var isOrdered: Bool
        public var items: [Item]
    }

    public struct Item: Equatable, Sendable {
        /// The number an ordered item shows: the list's written start plus
        /// the item's place.
        public var ordinal: Int
        /// Nil for an ordinary item, else whether its box is ticked.
        public var checked: Bool?
        public var blocks: [Block]
    }

    public struct Table: Equatable, Sendable {
        public enum Alignment: Equatable, Sendable {
            case left, center, right
        }

        public var alignments: [Alignment]
        public var header: [AttributedString]
        public var rows: [[AttributedString]]
    }

    public var blocks: [Block]

    /// `baseURL`, the file's own URL, resolves relative links and images.
    public init(markdown: String, baseURL: URL? = nil) {
        var markdown = markdown
        var front: Block?
        if let (yaml, rest) = Self.splitFrontMatter(markdown) {
            front = .code(language: "yaml", yaml)
            markdown = rest
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed: [Block]
        if let string = try? AttributedString(markdown: markdown, options: options, baseURL: baseURL) {
            let runs = string.runs.map { run in
                Run(
                    path: Array((run.presentationIntent?.components ?? []).reversed()),
                    text: AttributedString(string[run.range]))
            }
            parsed = Self.blocks(runs[...], depth: 0)
        } else {
            parsed = markdown.isEmpty ? [] : [.code(language: nil, markdown)]
        }
        blocks = (front.map { [$0] } ?? []) + parsed
    }

    // MARK: Front matter

    /// The YAML between a first line of `---` and the next line of `---` or
    /// `...`, and the text after it.
    static func splitFrontMatter(_ markdown: String) -> (yaml: String, rest: String)? {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? $0.dropLast() : $0
        }[...]
        guard lines.first == "---" else { return nil }
        lines = lines.dropFirst()
        guard let end = lines.firstIndex(where: { $0 == "---" || $0 == "..." }) else { return nil }
        return (lines[..<end].joined(separator: "\n"), lines[(end + 1)...].joined(separator: "\n"))
    }

    // MARK: Blocks

    /// A run of text and the blocks it sits in, outermost first.
    private struct Run {
        var path: [PresentationIntent.IntentType]
        var text: AttributedString
    }

    /// The blocks at `depth` of the runs' paths. A run with no block there is
    /// an HTML block, which the parser gives none.
    private static func blocks(_ runs: ArraySlice<Run>, depth: Int) -> [Block] {
        groups(runs, depth: depth).compactMap { kind, runs in
            guard let kind else { return runs.first.flatMap { html($0.text) } }
            return block(kind, runs, depth: depth)
        }
    }

    private static func block(_ kind: PresentationIntent.Kind, _ runs: ArraySlice<Run>, depth: Int) -> Block? {
        switch kind {
        case .paragraph:
            return .paragraph(inline(runs))
        case .header(let level):
            return .heading(level: level, inline(runs))
        case .codeBlock(let language):
            var code = String(runs.map { String($0.text.characters) }.joined())
            if code.hasSuffix("\n") { code.removeLast() }
            return .code(language: language, code)
        case .thematicBreak:
            return .rule
        case .blockQuote:
            return .quote(blocks(runs, depth: depth + 1))
        case .orderedList, .unorderedList:
            return .list(List(isOrdered: kind == .orderedList, items: items(runs, depth: depth + 1)))
        case .table(let columns):
            return .table(table(runs, columns: columns, depth: depth + 1))
        default:
            return nil
        }
    }

    private static func items(_ runs: ArraySlice<Run>, depth: Int) -> [Item] {
        groups(runs, depth: depth).compactMap { kind, runs in
            guard case .listItem(let ordinal)? = kind else { return nil }
            var item = Item(ordinal: ordinal, checked: nil, blocks: blocks(runs, depth: depth + 1))
            if case .paragraph(let text)? = item.blocks.first, let (checked, rest) = task(text) {
                item.checked = checked
                item.blocks[0] = .paragraph(rest)
            }
            return item
        }
    }

    /// Whether `text` starts with a task marker, which is ticked, and the
    /// text after it.
    private static func task(_ text: AttributedString) -> (Bool, AttributedString)? {
        let start = String(text.characters.prefix(4))
        let checked: Bool
        switch start {
        case "[ ] ": checked = false
        case "[x] ", "[X] ": checked = true
        default: return nil
        }
        return (checked, AttributedString(text[text.characters.index(text.startIndex, offsetBy: 4)...]))
    }

    private static func table(
        _ runs: ArraySlice<Run>, columns: [PresentationIntent.TableColumn], depth: Int
    ) -> Table {
        var table = Table(
            alignments: columns.map { column in
                switch column.alignment {
                case .center: .center
                case .right: .right
                default: .left
                }
            },
            header: [], rows: [])
        for (kind, row) in groups(runs, depth: depth) where kind != nil {
            let cells = groups(row, depth: depth + 1).map { inline($0.runs) }
            if kind == .tableHeaderRow { table.header = cells } else { table.rows.append(cells) }
        }
        return table
    }

    /// Consecutive runs sharing a block at `depth`, with that block's kind;
    /// a run with no block at `depth` alone, with none.
    private static func groups(
        _ runs: ArraySlice<Run>, depth: Int
    ) -> [(kind: PresentationIntent.Kind?, runs: ArraySlice<Run>)] {
        var groups: [(kind: PresentationIntent.Kind?, runs: ArraySlice<Run>)] = []
        var start = runs.startIndex
        while start < runs.endIndex {
            guard depth < runs[start].path.count else {
                groups.append((nil, runs[start...start]))
                start += 1
                continue
            }
            let intent = runs[start].path[depth]
            var end = start + 1
            while end < runs.endIndex, depth < runs[end].path.count, runs[end].path[depth].identity == intent.identity {
                end += 1
            }
            groups.append((intent.kind, runs[start..<end]))
            start = end
        }
        return groups
    }

    // MARK: Inline text

    /// The runs as one string without their block structure or inline HTML
    /// tags.
    private static func inline(_ runs: ArraySlice<Run>) -> AttributedString {
        var text = AttributedString()
        for run in runs {
            if run.text.runs.first?.inlinePresentationIntent?.contains(.inlineHTML) == true { continue }
            var part = run.text
            part.presentationIntent = nil
            text.append(part)
        }
        return text
    }

    /// An HTML block as a paragraph of its text, or nothing when it has
    /// none, as a picture element has not.
    private static func html(_ text: AttributedString) -> Block? {
        let source = String(text.characters)
        let words = source.replacing(/<[^>]*>/, with: " ").split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        return .paragraph(AttributedString(words.joined(separator: " ")))
    }
}
