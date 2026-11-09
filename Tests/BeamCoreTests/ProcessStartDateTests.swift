import BeamCore
import Foundation
import Testing

struct ProcessStartDateTests {
    @Test func aChildStartsBetweenTheMomentsEitherSideOfItsLaunch() throws {
        let child = Process()
        child.executableURL = URL(filePath: "/bin/sleep")
        child.arguments = ["10"]
        let before = Date()
        try child.run()
        let after = Date()
        defer { child.terminate() }

        let start = try #require(ProcessInfo.startDate(of: child.processIdentifier))
        // The kernel keeps microseconds, so `before` may fall inside the one
        // the child started in.
        #expect(start >= before.addingTimeInterval(-0.000_001))
        #expect(start <= after)
    }

    @Test func aProcessThatDoesNotExistHasNoStartDate() throws {
        let child = Process()
        child.executableURL = URL(filePath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()

        #expect(ProcessInfo.startDate(of: child.processIdentifier) == nil)
    }
}
