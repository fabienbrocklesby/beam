import BeamCore
import Testing

struct AgentActivityTests {
    let first = Pane.ID()
    let second = Pane.ID()
    let third = Pane.ID()

    @Test func aPaneTakesTheStateItsAgentLastReported() {
        var activity = AgentActivity()
        activity.apply(.working, to: first)
        #expect(activity[first] == .working)
        activity.apply(.waiting(message: "Needs your permission to use Bash"), to: first)
        #expect(activity[first] == .waiting(message: "Needs your permission to use Bash"))
        activity.apply(.done(message: "All tests pass."), to: first)
        #expect(activity[first] == .done(message: "All tests pass."))
        #expect(activity[second] == nil)
    }

    /// That moment is when the user hears about it.
    @Test func applyingSaysWhenAPaneStartsNeedingTheUser() {
        var activity = AgentActivity()
        func apply(_ event: AgentReport.Event) -> Bool { activity.apply(event, to: first) }
        var reported = [
            apply(.working),
            apply(.waiting(message: "Needs your permission to use Bash")),
            apply(.waiting(message: "Claude needs your permission")),
            apply(.done(message: nil)),
            apply(.working),
            apply(.done(message: "Done.")),
        ]
        #expect(reported == [false, true, false, false, false, true])

        activity.acknowledge(first)
        reported = [apply(.idle), apply(.done(message: "Done again.")), apply(.started(session: nil))]
        #expect(reported == [false, true, false])
    }

    @Test func aNewOrEndedSessionHasNoState() {
        var activity = AgentActivity()
        activity.apply(.done(message: nil), to: first)
        activity.apply(.started(session: "abc"), to: first)
        #expect(activity[first] == nil)
        activity.apply(.working, to: first)
        activity.apply(.ended, to: first)
        #expect(activity[first] == nil)
    }

    @Test func goingIdleOnlyClearsATurnThatNeverReportedItsEnd() {
        var activity = AgentActivity()
        activity.apply(.working, to: first)
        activity.apply(.idle, to: first)
        #expect(activity[first] == nil)

        activity.apply(.done(message: "Done."), to: second)
        activity.apply(.idle, to: second)
        #expect(activity[second] == .done(message: "Done."))

        activity.apply(.waiting(message: "Question"), to: third)
        activity.apply(.idle, to: third)
        #expect(activity[third] == .waiting(message: "Question"))
    }

    @Test func seeingAPaneClearsAFinishedTurnButNotAWaitingOne() {
        var activity = AgentActivity()
        activity.apply(.done(message: nil), to: first)
        activity.apply(.waiting(message: "Question"), to: second)
        activity.apply(.working, to: third)
        for pane in [first, second, third] { activity.acknowledge(pane) }
        #expect(activity[first] == nil)
        #expect(activity[second] == .waiting(message: "Question"))
        #expect(activity[third] == .working)
    }

    @Test func forgettingAPaneDropsItsState() {
        var activity = AgentActivity()
        activity.apply(.working, to: first)
        activity.forget(first)
        #expect(activity[first] == nil)
    }

    @Test func aWorkspaceShowsItsMostUrgentPane() {
        var activity = AgentActivity()
        #expect(activity.summary(of: [first, second, third]) == nil)
        activity.apply(.working, to: first)
        #expect(activity.summary(of: [first, second, third]) == .working)
        activity.apply(.done(message: "Done."), to: second)
        #expect(activity.summary(of: [first, second, third]) == .done(message: "Done."))
        activity.apply(.waiting(message: "Question"), to: third)
        #expect(activity.summary(of: [first, second, third]) == .waiting(message: "Question"))
        #expect(activity.summary(of: [first]) == .working)
    }

    @Test func theNextPaneNeedingYouComesAfterTheCurrentOneAndWrapsRound() {
        var activity = AgentActivity()
        let order = [first, second, third]
        #expect(activity.next(after: first, in: order) == nil)

        activity.apply(.working, to: second)
        #expect(activity.next(after: first, in: order) == nil)

        activity.apply(.done(message: nil), to: first)
        activity.apply(.waiting(message: "Question"), to: third)
        #expect(activity.next(after: first, in: order) == third)
        #expect(activity.next(after: third, in: order) == first)
        #expect(activity.next(after: second, in: order) == third)
        #expect(activity.next(after: nil, in: order) == first)
    }

    @Test func theOnlyPaneNeedingYouIsNextEvenWhenItIsCurrent() {
        var activity = AgentActivity()
        activity.apply(.waiting(message: "Question"), to: second)
        #expect(activity.next(after: second, in: [first, second, third]) == second)
    }

    @Test func aPaneOutsideTheOrderIsNeverNext() {
        var activity = AgentActivity()
        activity.apply(.done(message: nil), to: third)
        #expect(activity.next(after: nil, in: [first, second]) == nil)
    }
}
