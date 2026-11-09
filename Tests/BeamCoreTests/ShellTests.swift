import BeamCore
import Testing

struct ShellTests {
    @Test func plainPathIsUnchanged() {
        #expect(Shell.escape("/Users/me/Desktop/shot.png") == "/Users/me/Desktop/shot.png")
    }

    @Test func spacesAndQuotesAreEscaped() {
        #expect(Shell.escape("/tmp/My Shot's.png") == #"/tmp/My\ Shot\'s.png"#)
    }

    @Test(arguments: Array(#"\ ()[]{}<>"'`!#$&;|*?"#) + ["\t"])
    func shellMetacharacterIsEscaped(character: Character) {
        #expect(Shell.escape("a\(character)b") == "a\\\(character)b")
    }

    @Test(arguments: ["\n", "\r"])
    func lineBreaksAreSingleQuotedSoTheyStayInTheArgument(lineBreak: String) {
        #expect(Shell.escape("/tmp/a\(lineBreak)b's") == "'/tmp/a\(lineBreak)b'\\''s'")
    }

    @Test func unicodeIsLeftAlone() {
        #expect(Shell.escape("/tmp/café/日本.txt") == "/tmp/café/日本.txt")
    }
}
