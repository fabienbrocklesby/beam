import BeamCore
import Foundation
import Testing

/// A class, so each test's instance can take its folder with it.
final class VersionTests {
    /// This test's stand-in programs, removed when it ends.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "beam-version-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func readsTheVersionEachAgentPrints() {
        #expect(Version(in: "2.1.281 (Claude Code)")?.description == "2.1.281")
        #expect(Version(in: "codex-cli 0.166.0")?.description == "0.166.0")
        #expect(Version(in: "0.67.0\n")?.description == "0.67.0")
        #expect(Version(in: "kimi, version 1.52.0")?.description == "1.52.0")
    }

    @Test func readsTheVersionsRegistriesGive() {
        #expect(Version(in: "v22.1.0")?.description == "22.1.0")
        // A Homebrew formula's revision and a cask's build after the comma
        // are not part of the version the program reports.
        #expect(Version(in: "0.67.0_1")?.description == "0.67.0")
        #expect(Version(in: "1.4.2,8812")?.description == "1.4.2")
        #expect(Version(in: "0.68.0-preview.1")?.description == "0.68.0-preview.1")
    }

    @Test func textWithoutADottedVersionHasNone() {
        #expect(Version(in: "") == nil)
        #expect(Version(in: "command not found") == nil)
        #expect(Version(in: "error 404") == nil)
    }

    @Test func versionsOrderByEachNumber() throws {
        let order = ["0.9.9", "0.10.0", "0.166.0", "0.167.0", "2.1.281", "2.1.319", "10.0"]
        let versions = try order.map { try #require(Version(in: $0)) }
        #expect(versions == versions.sorted())
        #expect(versions.shuffled().sorted() == versions)
    }

    @Test func missingNumbersCountAsZero() throws {
        #expect(try #require(Version(in: "1.2")) == #require(Version(in: "1.2.0")))
        #expect(try #require(Version(in: "1.2")) < #require(Version(in: "1.2.1")))
    }

    @Test func aPrereleaseComesBeforeItsRelease() throws {
        let order = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0"]
        let versions = try order.map { try #require(Version(in: $0)) }
        #expect(versions == versions.sorted())
        #expect(try #require(Version(in: "0.9.0")) < #require(Version(in: "1.0.0-alpha")))
    }

    /// A stand-in for an agent's program that runs `body`.
    func makeProgram(_ body: String) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let program = folder.appending(path: "agent-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        return program.path
    }

    @Test func aProgramReportsItsVersionWhenAsked() throws {
        let program = try makeProgram(#"[ "$1" = --version ] && echo "codex-cli 0.166.0""#)
        #expect(Version.reported(by: program, environment: [:], timeout: 10)?.description == "0.166.0")
    }

    @Test func theProgramRunsWithTheEnvironmentItIsGiven() throws {
        let program = try makeProgram(#"echo "$AGENT_VERSION""#)
        let version = Version.reported(by: program, environment: ["AGENT_VERSION": "3.2.1"], timeout: 10)
        #expect(version?.description == "3.2.1")
    }

    @Test func aProgramThatFailsOrHangsReportsNothing() throws {
        #expect(Version.reported(by: try makeProgram("echo 1.2.3; exit 1"), environment: [:], timeout: 10) == nil)
        #expect(Version.reported(by: "/no/such/agent", environment: [:], timeout: 10) == nil)
        let start = ContinuousClock.now
        let hangs = try makeProgram("trap '' TERM; while :; do sleep 1; done")
        #expect(Version.reported(by: hangs, environment: [:], timeout: 0.2) == nil)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    /// Update checkers that npm packages start in the background inherit
    /// the program's output and outlive it.
    @Test func aChildLeftRunningDoesNotHoldTheAnswerUp() throws {
        let program = try makeProgram("(sleep 10) & echo 4.5.6")
        let start = ContinuousClock.now
        #expect(Version.reported(by: program, environment: [:], timeout: 10)?.description == "4.5.6")
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
