import BeamCore
import Foundation
import Testing

struct FileMentionTests {
    private func mention(_ text: String) -> FileMention? {
        FileMention(text, home: "/Users/me")
    }

    @Test func aPathIsTakenAsWritten() {
        #expect(mention("/Users/me/Code/beam/README.md") == .file("/Users/me/Code/beam/README.md"))
        #expect(mention("Sources/BeamCore/Pane.swift") == .file("Sources/BeamCore/Pane.swift"))
        #expect(mention("shot.png") == .file("shot.png"))
        #expect(mention("../notes.md") == .file("../notes.md"))
    }

    @Test func theHomeFolderIsExpanded() {
        #expect(mention("~/Desktop/shot.png") == .file("/Users/me/Desktop/shot.png"))
        #expect(mention("~") == .file("/Users/me"))
        #expect(mention("$HOME/notes.md") == .file("/Users/me/notes.md"))
    }

    /// `$PWD` is wherever the text was written, which a relative path already means.
    @Test func theWorkingDirectoryVariableMeansRelative() {
        #expect(mention("$PWD/src/main.zig") == .file("src/main.zig"))
    }

    /// Compilers, linters and agents point at a line, and sometimes a column.
    @Test func aLineAndColumnAreDropped() {
        #expect(mention("Sources/Beam/App/main.swift:12") == .file("Sources/Beam/App/main.swift"))
        #expect(mention("lib/terminal.zig:42:10") == .file("lib/terminal.zig"))
        #expect(mention("/Users/me/a.rb:7:") == .file("/Users/me/a.rb"))
    }

    @Test func aFileURLIsItsPath() {
        #expect(mention("file:///Users/me/shot.png") == .file("/Users/me/shot.png"))
        #expect(mention("file:///Users/me/my%20shot.png") == .file("/Users/me/my shot.png"))
        #expect(mention("FILE:///Users/me/a.pdf") == .file("/Users/me/a.pdf"))
    }

    /// The schemes Ghostty's link regex matches, other than `file:`.
    @Test func aWebAddressIsNotAPath() throws {
        #expect(
            mention("https://example.com/shot.png") == .web(try #require(URL(string: "https://example.com/shot.png"))))
        #expect(mention("mailto:me@example.com") == .web(try #require(URL(string: "mailto:me@example.com"))))
        #expect(mention("ssh://host") == .web(try #require(URL(string: "ssh://host"))))
    }

    /// A dotted name followed by a line number parses as a URL scheme, which
    /// it is not.
    @Test func aNameThatLooksLikeASchemeIsStillAPath() {
        #expect(mention("file.rb:1") == .file("file.rb"))
        #expect(mention("main.swift:12:4") == .file("main.swift"))
    }

    @Test func nothingIsNoMention() {
        #expect(mention("") == nil)
        #expect(mention(":12") == nil)
        #expect(mention("https://") == nil)
    }

    // MARK: Finding mentions in text

    @Test func aMessageNamesFilesInCodeSpansLinksAndWords() {
        let message = """
            Saved the screenshot as `shot-dark.png`, with ![the chart](out/chart.svg) beside it.
            The report is at /tmp/session/report.pdf.
            """
        #expect(FileMention.names(in: message) == ["shot-dark.png", "out/chart.svg", "/tmp/session/report.pdf"])
    }

    @Test func punctuationAroundANameIsNotPartOfIt() {
        #expect(
            FileMention.names(in: "(see **shot.png**), then \"notes.md\"; or 'a.pdf'!") == [
                "shot.png", "notes.md", "a.pdf",
            ])
        #expect(FileMention.names(in: "Fixed main.swift:12: a crash.") == ["main.swift:12"])
    }

    /// A name with a space only comes through whole in a code span, which
    /// may as well be a command, so its words count too. The resolver drops
    /// whichever names nothing.
    @Test func aCodeSpanWithASpaceIsANameAndSoAreItsWords() {
        #expect(FileMention.names(in: "Open `Screen Shot 1.png` now") == ["Screen Shot 1.png", "1.png"])
        #expect(FileMention.names(in: "Run `open shot.png` to see it") == ["open shot.png", "shot.png"])
    }

    @Test func wordsThatCannotBeFilesAreLeftOut() {
        #expect(FileMention.names(in: "Done. All tests pass, version 0.1.0, run `make check`.") == [])
        #expect(FileMention.names(in: "See https://example.com/shot.png and mailto:me@example.com") == [])
    }

    /// Code blocks are code, not names.
    @Test func aCodeBlockIsSkipped() {
        let message = """
            Added it:
            ```swift
            let url = folder.appendingPathComponent("x.png")
            ```
            Wrote `x.png`.
            """
        #expect(FileMention.names(in: message) == ["x.png"])
    }

    @Test func eachNameComesOnceInTheOrderFirstWritten() {
        #expect(FileMention.names(in: "a.png, b.png and a.png again") == ["a.png", "b.png"])
    }

    @Test func aShellCommandNamesTheFilesItWrites() {
        #expect(
            FileMention.names(in: "mkdir -p shots && printf 'x' > shots/pic.png") == ["shots/pic.png"])
        #expect(
            FileMention.names(in: "screencapture -x -l 6539 /tmp/s/shot.png 2>/dev/null; cp a.txt --to=out/b.txt")
                == ["/tmp/s/shot.png", "/dev/null", "a.txt", "out/b.txt"])
    }

    /// Codex edits files with `apply_patch`, whose input names them.
    @Test func aPatchNamesTheFilesItAddsUpdatesAndMoves() {
        let patch = """
            *** Begin Patch
            *** Add File: diagram.svg
            +<svg xmlns="http://www.w3.org/2000/svg"/>
            *** Update File: src/a.swift
            *** Move to: src/b.swift
            @@
            -old
            +new
            *** Delete File: old.txt
            *** End Patch
            """
        #expect(FileMention.names(inPatch: patch) == ["diagram.svg", "src/a.swift", "src/b.swift"])
    }

    /// macOS files `.ts` and `.mts` as video, so the tray asks before
    /// trusting the type.
    @Test func typeScriptIsToldApartFromVideo() {
        #expect(FileMention.isTypeScript("src/app.ts"))
        #expect(FileMention.isTypeScript("/r/vite.config.mts"))
        #expect(FileMention.isTypeScript("INDEX.TS"))
        #expect(!FileMention.isTypeScript("clip.mp4"))
        #expect(!FileMention.isTypeScript("shot.png"))
        #expect(!FileMention.isTypeScript("ts"))
    }
}
