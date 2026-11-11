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
}
