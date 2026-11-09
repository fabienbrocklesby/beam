import BeamCore
import Testing

struct ReplaySequenceTests {
    @Test func resetClearsTheScreenTheScrollbackAndEveryMode() {
        #expect(ReplaySequence.reset == Array("\u{1b}c\u{1b}[3J".utf8))
    }

    @Test func onlyPaletteEntriesAnAppChangedAreSent() {
        let defaults = (0..<256).map { ReplaySequence.Color(red: UInt8($0), green: 0, blue: 0) }
        var current = defaults
        current[1] = ReplaySequence.Color(red: 0xAB, green: 0x0C, blue: 0xFF)
        current[200] = ReplaySequence.Color(red: 1, green: 2, blue: 3)
        let sequence = String(decoding: ReplaySequence.palette(current, defaults: defaults), as: UTF8.self)
        #expect(sequence == "\u{1b}]4;1;rgb:ab/0c/ff\u{1b}\\\u{1b}]4;200;rgb:01/02/03\u{1b}\\")
    }

    @Test func anUnchangedPaletteSendsNothing() {
        let defaults = (0..<256).map { ReplaySequence.Color(red: 0, green: UInt8($0), blue: 0) }
        #expect(ReplaySequence.palette(defaults, defaults: defaults).isEmpty)
    }

    @Test func onlyACursorAtItsPromptGetsTheInputStartMark() {
        #expect(String(decoding: ReplaySequence.inputStart(atPrompt: true), as: UTF8.self) == "\u{1b}]133;B\u{1b}\\")
        #expect(ReplaySequence.inputStart(atPrompt: false) == [])
    }

    @Test func theTitleIsSetWithControlCharactersDropped() {
        #expect(ReplaySequence.title("") == [])
        #expect(
            String(decoding: ReplaySequence.title("✳ Fix\u{07}the\u{1b}bug"), as: UTF8.self)
                == "\u{1b}]2;✳ Fixthebug\u{1b}\\")
    }
}
