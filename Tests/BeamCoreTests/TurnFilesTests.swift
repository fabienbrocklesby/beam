import BeamCore
import Testing

struct TurnFilesTests {
    private let pane = Pane.ID()

    private func report(
        _ event: AgentReport.Event, _ names: [String]? = nil, in directory: String? = "/r", pane: Pane.ID? = nil
    ) -> AgentReport {
        AgentReport(
            pane: pane ?? self.pane, agent: .claude, event: event,
            files: names.map { AgentReport.Files(directory: directory, names: $0) })
    }

    @Test func theFilesToolsTouchedComeWithTheNamesTheReplyMentions() {
        var turns = TurnFiles(home: "/Users/me")
        #expect(turns.record(report(.working, ["/s/notes.md"])) == nil)
        #expect(turns.record(report(.working)) == nil)
        #expect(
            turns.record(report(.done(message: "Saved."), ["shot.png"]))
                == TurnFiles.Lookup(names: ["shot.png"], directory: "/r", touched: ["/s/notes.md"]))
    }

    /// Each tool result's names start from its own directory.
    @Test func touchedFilesAreKeptAbsoluteAndOnce() {
        var turns = TurnFiles(home: "/Users/me")
        turns.record(report(.working, ["shots/pic.png", "~/a.png", "https://example.com/b.png"], in: "/r"))
        turns.record(report(.working, ["/r/shots/pic.png", "c.txt:12"], in: "/r"))
        turns.record(report(.working, ["d.txt"], in: nil))
        #expect(
            turns.record(report(.done(message: nil), ["pic.png"]))?.touched == [
                "/r/shots/pic.png", "/Users/me/a.png", "/r/c.txt",
            ])
    }

    /// So it replaces the last turn's previews with none.
    @Test func aTurnWhoseReplyNamesNothingStillEndsWithALookup() {
        var turns = TurnFiles(home: "/Users/me")
        turns.record(report(.working, ["/s/notes.md"]))
        #expect(
            turns.record(report(.done(message: "Done.")))
                == TurnFiles.Lookup(names: [], directory: nil, touched: ["/s/notes.md"]))
    }

    @Test func aTurnForgetsWhatTheLastOneTouched() {
        var turns = TurnFiles(home: "/Users/me")
        turns.record(report(.working, ["/s/notes.md"]))
        turns.record(report(.done(message: nil)))
        #expect(turns.record(report(.done(message: nil), ["shot.png"]))?.touched == [])
    }

    @Test func aNewSessionForgetsTheTurnItInterrupted() {
        var turns = TurnFiles(home: "/Users/me")
        turns.record(report(.working, ["/s/notes.md"]))
        turns.record(report(.started(session: "b")))
        #expect(turns.record(report(.done(message: nil), ["shot.png"]))?.touched == [])
    }

    @Test func eachPaneHasItsOwnTurn() {
        var turns = TurnFiles(home: "/Users/me")
        let other = Pane.ID()
        turns.record(report(.working, ["/s/notes.md"]))
        turns.record(report(.working, ["/t/plan.md"], pane: other))
        #expect(turns.record(report(.done(message: nil), ["a.png"], pane: other))?.touched == ["/t/plan.md"])
        #expect(turns.record(report(.done(message: nil), ["a.png"]))?.touched == ["/s/notes.md"])
    }

    @Test func aForgottenPaneStartsAfresh() {
        var turns = TurnFiles(home: "/Users/me")
        turns.record(report(.working, ["/s/notes.md"]))
        turns.forget(pane)
        #expect(turns.record(report(.done(message: nil), ["a.png"]))?.touched == [])
    }
}
