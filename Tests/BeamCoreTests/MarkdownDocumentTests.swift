import BeamCore
import Foundation
import Testing

struct MarkdownDocumentTests {
    typealias Block = MarkdownDocument.Block

    func text(_ string: AttributedString) -> String { String(string.characters) }

    /// Blocks reduced to their kind and text, so a check reads as an outline.
    func outline(_ blocks: [Block]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .heading(let level, let content): ["h\(level) \(text(content))"]
            case .paragraph(let content): ["p \(text(content))"]
            case .code(let language, let code): ["code(\(language ?? "")) \(code)"]
            case .quote(let inner): outline(inner).map { "> " + $0 }
            case .list(let list):
                list.items.flatMap { item in
                    let marker =
                        switch item.checked {
                        case true: "[x]"
                        case false: "[ ]"
                        case nil: list.isOrdered ? "\(item.ordinal)." : "-"
                        }
                    return outline(item.blocks).map { "\(marker) " + $0 }
                }
            case .table(let table): ["table \(table.header.map(text)) \(table.rows.count) rows"]
            case .rule: ["rule"]
            }
        }
    }

    func outline(_ markdown: String) -> [String] { outline(MarkdownDocument(markdown: markdown).blocks) }

    @Test func headingsParagraphsAndRules() {
        let markdown = "# Beam\n\nA terminal.\n\nSetext\n------\n\n---\n\nEnd."
        #expect(outline(markdown) == ["h1 Beam", "p A terminal.", "h2 Setext", "rule", "p End."])
    }

    @Test func nestedListsKeepTheirNumbers() {
        let markdown = "3. three\n4. four\n   - nested a\n   - nested b\n5. five"
        #expect(
            outline(markdown) == [
                "3. p three", "4. p four", "4. - p nested a", "4. - p nested b", "5. p five",
            ])
    }

    @Test func taskListItemsBecomeCheckboxes() {
        let markdown = "- [ ] write the tests\n- [x] run the spike\n- plain item"
        #expect(outline(markdown) == ["[ ] p write the tests", "[x] p run the spike", "- p plain item"])
    }

    @Test func codeBlocksKeepTheirLanguageAndText() {
        let markdown = "```swift\nlet x = 1\nprint(x)\n```\n\n    indented"
        #expect(outline(markdown) == ["code(swift) let x = 1\nprint(x)", "code() indented"])
    }

    @Test func quotesHoldBlocks() {
        let markdown = "> A quote\n>\n> - with a list"
        #expect(outline(markdown) == ["> p A quote", "> - p with a list"])
    }

    @Test func tablesKeepAlignmentHeaderAndRows() throws {
        let markdown = "| Unit | Status | RAM |\n|:--|:-:|--:|\n| 9 | Done | 78 |\n| 11 | **Planned** | n/a |"
        let blocks = MarkdownDocument(markdown: markdown).blocks
        guard case .table(let table) = try #require(blocks.first) else {
            Issue.record("not a table: \(blocks)")
            return
        }
        #expect(table.alignments == [.left, .center, .right])
        #expect(table.header.map(text) == ["Unit", "Status", "RAM"])
        #expect(table.rows.map { $0.map(text) } == [["9", "Done", "78"], ["11", "Planned", "n/a"]])
        #expect(table.rows[1][1].runs.first?.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test func frontMatterBecomesACodeBlockFirst() {
        let markdown = "---\nname: beam\ntags: [a, b]\n---\n\n# Title"
        #expect(outline(markdown) == ["code(yaml) name: beam\ntags: [a, b]", "h1 Title"])
    }

    /// Without a closing line it is an ordinary rule.
    @Test func anOpeningRuleWithoutAnEndIsNotFrontMatter() {
        #expect(outline("---\n\nText") == ["rule", "p Text"])
    }

    @Test func inlineHTMLTagsAreDroppedAndTheirTextKept() {
        #expect(outline("Press <kbd>Cmd</kbd> and <b>D</b>.") == ["p Press Cmd and D."])
    }

    /// The README starts with a picture element, which has no text.
    @Test func anHTMLBlockShowsItsTextOrNothing() {
        let markdown =
            "<p align=\"center\">\n  <img src=\"logo.png\" alt=\"Beam\">\n</p>\n\n<div>\n  <b>Bold</b> words\n</div>\n\nAfter."
        #expect(outline(markdown) == ["p Bold words", "p After."])
    }

    @Test func emphasisLinksAndImagesStayAsAttributes() throws {
        let base = URL(filePath: "/Users/me/project/README.md")
        let document = MarkdownDocument(
            markdown: "Some **bold**, `code`, ~~gone~~, a [plan](docs/PLAN.md) and ![shot](shot.png).", baseURL: base)
        guard case .paragraph(let content) = try #require(document.blocks.first) else {
            Issue.record("not a paragraph")
            return
        }
        #expect(text(content) == "Some bold, code, gone, a plan and shot.")
        let intents = content.runs.compactMap(\.inlinePresentationIntent)
        #expect(intents == [.stronglyEmphasized, .code, .strikethrough])
        let link = try #require(content.runs.compactMap(\.link).first)
        #expect(link.absoluteURL.path == "/Users/me/project/docs/PLAN.md")
        #expect(content.runs.compactMap(\.imageURL).first?.absoluteURL.path == "/Users/me/project/shot.png")
    }

    @Test func aHardBreakIsALineBreakInTheParagraph() {
        #expect(outline("one  \ntwo\nthree") == ["p one\ntwo three"])
    }

    @Test func footnotesAndMathStayAsWritten() {
        #expect(outline("A claim[^1] and $x^2$.") == ["p A claim[^1] and $x^2$."])
    }

    @Test func anEmptyFileHasNoBlocks() {
        #expect(MarkdownDocument(markdown: "").blocks.isEmpty)
    }
}
