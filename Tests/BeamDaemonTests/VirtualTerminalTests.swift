import BeamCore
import Testing

@testable import BeamDaemon

@MainActor
struct VirtualTerminalTests {
    private let size = WindowSize(columns: 80, rows: 24, width: 800, height: 480)

    /// A pane fed the replay, as beam-attach feeds Ghostty's terminal.
    private func reattached(after output: String) throws -> VirtualTerminal {
        let session = try VirtualTerminal(size: size)
        Array(output.utf8).withUnsafeBytes { session.write($0) }
        let pane = try VirtualTerminal(size: size)
        session.replay().withUnsafeBytes { pane.write($0) }
        return pane
    }

    // Ghostty asks before closing a pane whose cursor is not at a prompt, so
    // an idle shell that lost its prompt marks would ask as if busy.
    @Test func anIdleShellIsStillAtItsPromptAfterTheReplay() throws {
        let pane = try reattached(after: "\u{1b}]133;A\u{07}~ % \u{1b}]133;B\u{07}")
        #expect(pane.isCursorAtPrompt)
    }

    @Test func aRunningCommandIsNotAtAPromptAfterTheReplay() throws {
        let pane = try reattached(after: "\u{1b}]133;A\u{07}~ % \u{1b}]133;B\u{07}sleep 9\r\n\u{1b}]133;C\u{07}")
        #expect(!pane.isCursorAtPrompt)
    }

    @Test func outputWithoutMarksIsNotAPrompt() throws {
        let pane = try reattached(after: "hello\r\n")
        #expect(!pane.isCursorAtPrompt)
    }
}
