import BeamCore
import Testing

struct AgentReportsTests {
    let pane = Pane.ID()

    private func report(_ event: AgentReport.Event) -> AgentReport {
        AgentReport(pane: pane, agent: .claude, event: event)
    }

    /// The point of keeping so little: a Beam that only hears the kept
    /// reports ends up where one that heard every report did.
    @Test func replayingWhatIsKeptGivesTheStateEveryReportGave() {
        let histories: [[AgentReport.Event]] = [
            [],
            [.started(session: "a")],
            [.started(session: "a"), .working],
            [.started(session: "a"), .working, .waiting(message: "Needs your permission")],
            [.started(session: "a"), .working, .done(message: "Done.")],
            [.started(session: "a"), .working, .done(message: "Done."), .idle],
            [.started(session: "a"), .working, .idle],
            [.working, .waiting(message: "Needs your permission"), .idle],
            [.started(session: "a"), .working, .started(session: "b")],
            [.started(session: "a"), .working, .done(message: nil), .ended],
            [.working, .done(message: "Done."), .working],
        ]
        for history in histories {
            var everything = AgentActivity()
            var reports = AgentReports()
            for event in history {
                everything.apply(event, to: pane)
                reports.record(report(event))
            }
            var replayed = AgentActivity()
            for kept in reports.latest(for: pane) { replayed.apply(kept.event, to: pane) }
            #expect(replayed == everything, "\(history)")
        }
    }

    @Test func theLatestStartNamesTheConversationAndComesFirst() {
        var reports = AgentReports()
        reports.record(report(.started(session: "a")))
        reports.record(report(.working))
        reports.record(report(.started(session: "b")))
        reports.record(report(.waiting(message: "Needs your permission")))
        #expect(
            reports.latest(for: pane) == [
                report(.started(session: "b")), report(.waiting(message: "Needs your permission")),
            ])
    }

    @Test func eachPaneKeepsItsOwn() {
        var reports = AgentReports()
        let other = Pane.ID()
        reports.record(report(.working))
        reports.record(AgentReport(pane: other, agent: .codex, event: .done(message: nil)))
        #expect(reports.latest(for: pane) == [report(.working)])
        #expect(reports.latest(for: other) == [AgentReport(pane: other, agent: .codex, event: .done(message: nil))])
    }

    @Test func aForgottenPaneHasNothing() {
        var reports = AgentReports()
        reports.record(report(.started(session: "a")))
        reports.record(report(.working))
        reports.forget(pane)
        #expect(reports.latest(for: pane).isEmpty)
    }
}
