import BeamCore
import Foundation
import Testing

struct LoginShellTests {
    /// A stand-in for the user's shell that runs `body` with the probe's
    /// arguments as `$1` to `$4`.
    func makeShell(_ body: String) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: "beam-login-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shell = folder.appending(path: "shell")
        try "#!/bin/sh\n\(body)\n".write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        return shell.path
    }

    /// Runs the probe's command with plain sh, so no rc file touches PATH,
    /// and only when asked for an interactive login shell.
    let loginShell = #"[ "$1 $2 $3" = "-l -i -c" ] || exit 1; exec /bin/sh -c "$4""#

    @Test func readsThePathAnInteractiveLoginShellBuilds() throws {
        let shell = try makeShell(loginShell)
        #expect(LoginShell.path(shell: shell, environment: ["PATH": "/one:/two"], timeout: 10) == "/one:/two")
    }

    @Test func whatRcFilesPrintStaysOutOfThePath() throws {
        let shell = try makeShell("echo welcome; echo oops >&2; " + loginShell)
        #expect(LoginShell.path(shell: shell, environment: ["PATH": "/one"], timeout: 10) == "/one")
    }

    @Test func aShellThatFailsGivesNoPath() throws {
        let shell = try makeShell("exit 1")
        #expect(LoginShell.path(shell: shell, environment: ["PATH": "/one"], timeout: 10) == nil)
        #expect(LoginShell.path(shell: "/no/such/shell", environment: [:], timeout: 10) == nil)
    }

    @Test func aShellThatHangsIsGivenUpOn() throws {
        // Ignores SIGTERM, as interactive shells do.
        let shell = try makeShell("trap '' TERM; while :; do sleep 1; done")
        let start = ContinuousClock.now
        #expect(LoginShell.path(shell: shell, environment: [:], timeout: 0.2) == nil)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
