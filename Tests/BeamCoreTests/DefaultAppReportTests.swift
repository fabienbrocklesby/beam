import BeamCore
import Foundation
import Testing

struct DefaultAppReportTests {
    static let beam = "/Applications/Beam.app"

    @Test func everyKindSetSaysSoAndNothingMore() {
        let report = DefaultAppReport(
            [("PDFs", .opens(Self.beam)), ("Markdown", .opens(Self.beam)), ("plain text", .opens(Self.beam))],
            beam: Self.beam)
        #expect(report.message == "Beam is now the default app for PDFs, Markdown and plain text.")
        #expect(report.details == "")
    }

    /// A default names a bundle ID and a version, so another copy of Beam at
    /// the same version can be the one Finder picks.
    @Test func anotherCopyOpeningAKindIsNamedOnce() {
        let other = "/Users/me/Code/beam/build/Beam.app"
        let report = DefaultAppReport(
            [("PDFs", .opens(other)), ("Markdown", .opens(other)), ("plain text", .opens(Self.beam))],
            beam: Self.beam)
        #expect(report.message == "Beam is now the default app for PDFs, Markdown and plain text.")
        #expect(report.details == "Finder will open PDFs and Markdown in the copy of Beam at \(other).")
    }

    /// macOS asks before it replaces some defaults, plain text always, and
    /// answers a kept app, or a question it could not ask, with a cancel.
    @Test func aKindMacOSKeptIsNotAFailure() {
        let report = DefaultAppReport(
            [("PDFs", .opens(Self.beam)), ("Markdown", .opens(Self.beam)), ("plain text", .kept)], beam: Self.beam)
        #expect(report.message == "Beam is now the default app for PDFs and Markdown.")
        #expect(report.details == "macOS kept the current app for plain text.")
    }

    @Test func nothingSetSaysSo() {
        let report = DefaultAppReport(
            [("PDFs", .kept), ("Markdown", .failed("Launch Services is not running.")), ("plain text", .kept)],
            beam: Self.beam)
        #expect(report.message == "Beam was not made the default app.")
        #expect(
            report.details
                == "macOS kept the current app for PDFs and plain text.\nMarkdown: Launch Services is not running.")
    }

    /// As NSWorkspace reported it on macOS 27: a Cocoa error wrapping
    /// `userCanceledErr`.
    @Test func aCancelFromLaunchServicesMeansKept() {
        let cancel = NSError(
            domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -128)])
        #expect(DefaultAppReport.Outcome(cancel) == .kept)
        #expect(DefaultAppReport.Outcome(CocoaError(.userCancelled)) == .kept)
        let other = NSError(domain: NSOSStatusErrorDomain, code: -10814)
        #expect(DefaultAppReport.Outcome(other) == .failed(other.localizedDescription))
    }
}
