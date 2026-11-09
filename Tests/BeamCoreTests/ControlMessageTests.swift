import BeamCore
import Foundation
import Testing

/// What Beam and beamd say to each other once a connection has opened as a
/// control connection, and what `beam hook` sends.
struct ControlMessageTests {
    let pane = Pane.ID()

    @Test func requestsTravelAsJSONInControlFrames() throws {
        for request in [ControlRequest.list, .end(pane: pane), .endAll] {
            let frame = try DaemonFrame(.control, encoding: request)
            #expect(frame.kind == .control)
            #expect(try frame.decode(ControlRequest.self) == request)
        }
    }

    @Test func eventsTravelAsJSONInControlFrames() throws {
        let started = AgentReport(pane: pane, agent: .claude, event: .started(session: "abc"))
        let waiting = AgentReport(pane: pane, agent: .claude, event: .waiting(message: "Needs your permission"))
        let events = [
            ControlEvent.sessions([ControlEvent.Session(pane: pane, reports: [started, waiting])]),
            .sessions([]),
            .report(waiting),
        ]
        for event in events {
            let frame = try DaemonFrame(.control, encoding: event)
            #expect(try frame.decode(ControlEvent.self) == event)
        }
    }

    @Test func aReportTravelsAsJSONInAReportFrame() throws {
        let report = AgentReport(pane: pane, agent: .codex, event: .done(message: nil))
        let frame = try DaemonFrame(.report, encoding: report)
        #expect(frame.bytes.first == 5)
        #expect(try frame.decode(AgentReport.self) == report)
    }

    @Test func controlAndReportKindsHaveFixedNumbers() {
        #expect(DaemonFrame.Kind.control.rawValue == 4)
        #expect(DaemonFrame.Kind.report.rawValue == 5)
    }

    @Test func aPayloadThatIsNotTheMessageFailsToDecode() {
        let frame = DaemonFrame(.control, payload: Array("nonsense".utf8))
        #expect(throws: (any Error).self) { try frame.decode(ControlRequest.self) }
    }
}
