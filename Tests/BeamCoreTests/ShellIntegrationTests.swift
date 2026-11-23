import BeamCore
import Foundation
import Testing

/// Runs the bundled zsh integration in a real zsh set up as a pane's is, with
/// stand-ins for the agents on its `PATH`.
///
/// A class, so each test's instance can take its folder with it.
@Suite(.timeLimit(.minutes(1)))
final class ShellIntegrationTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let integration = root.appending(path: "Resources/shell-integration/zsh").path
    private static let ghostty = root.appending(path: "vendor/ghostty/src/shell-integration/zsh").path

    private let hooks = AgentHooks(helper: "/Applications/Beam.app/Contents/Helpers/beam")
    /// This test's home, agents and output, removed when it ends.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "beam-zsh-\(UUID().uuidString)")
    private var home: URL { folder.appending(path: "home") }
    private var output: URL { folder.appending(path: "output") }

    init() throws {
        let bin = folder.appending(path: "bin")
        for directory in [home, bin] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Each stand-in writes what it was started with, an argument a line.
        for agent in ["claude", "codex"] {
            let path = bin.appending(path: agent).path
            try "#!/bin/sh\nprintf '%s\\n' \"$@\" >\"$BEAM_TEST_OUTPUT\"\n".write(
                toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The lines `line` leaves in the output file when typed at a zsh that
    /// starts as a pane's does, or nil when it leaves none. Whatever the
    /// integration prints stays out of it.
    private func lines(
        typing line: String, interactive: Bool = true, replacing replaced: [String: String?] = [:]
    ) throws -> [String]? {
        try? FileManager.default.removeItem(at: output)
        var environment = [
            "HOME": home.path,
            "PATH": folder.appending(path: "bin").path + ":/usr/bin:/bin",
            "BEAM_TEST_OUTPUT": output.path,
        ]
        environment.merge(hooks.environment) { $1 }
        environment.merge(
            PaneEnvironment.shellIntegration(
                shell: "/bin/zsh", zdotdir: nil, directory: Self.integration, ghostty: Self.ghostty)
        ) { $1 }
        for (name, value) in replaced { environment[name] = value }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = (interactive ? ["-i"] : []) + ["-c", line]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard let written = try? String(contentsOf: output, encoding: .utf8) else { return nil }
        return written.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    /// What typing `text` leaves as arguments: the shell expands it as it
    /// would any command's.
    private func expanded(_ text: String) throws -> [String]? {
        try lines(typing: #"printf '%s\n' \#(text) >"$BEAM_TEST_OUTPUT""#)
    }

    private func write(_ text: String, to file: String, in directory: URL? = nil) throws {
        try text.write(to: (directory ?? home).appending(path: file), atomically: true, encoding: .utf8)
    }

    /// A hand-typed agent used to start without hooks, so its pane showed no
    /// state: only the command Beam types carried them.
    @Test func anAgentTypedByHandStartsWithTheHooksBeamTypes() throws {
        for command in [
            "claude", "claude --continue", "claude --resume abc", "claude mcp list", "claude 'fix the bug'",
            "codex", "codex resume --last", "codex exec 'fix the bug'",
        ] {
            let typed = try lines(typing: command)
            #expect(typed != nil, "\(command)")
            #expect(typed == (try lines(typing: hooks.typed(command))), "\(command)")
        }
        #expect(
            try lines(typing: "claude --resume abc") == ["--settings", AgentHooks.claudeSettings, "--resume", "abc"])
        #expect(try lines(typing: "codex resume --last") == ["-c", AgentHooks.codexConfig, "resume", "--last"])
    }

    /// Claude Code reads only the last `--settings` it is given.
    @Test func settingsTheUserPassesThemselvesAreLeftAlone() throws {
        #expect(
            try lines(typing: "claude --settings mine.json --continue") == ["--settings", "mine.json", "--continue"])
        #expect(try lines(typing: "claude -p hi --settings=mine.json") == ["-p", "hi", "--settings=mine.json"])
    }

    @Test func anAgentStartsAsTypedWhereThePaneHasNoHooks() throws {
        let none: [String: String?] = ["BEAM_CLAUDE_SETTINGS": nil, "BEAM_CODEX_HOOKS": nil]
        #expect(try lines(typing: "claude --continue", replacing: none) == ["--continue"])
        #expect(try lines(typing: "codex resume --last", replacing: none) == ["resume", "--last"])
    }

    @Test func theUsersOwnFunctionOfTheSameNameReplacesBeams() throws {
        try write(#"codex() { command codex --mine "$@" }"#, to: ".zshrc")
        #expect(try lines(typing: "codex resume") == ["--mine", "resume"])
    }

    /// In `.zshenv` the alias is already there when the wrappers are defined.
    @Test(arguments: [".zshenv", ".zshrc"])
    func anAliasOfTheUsersStillGetsTheHooks(file: String) throws {
        try write("alias claude='claude --verbose'\n", to: file)
        #expect(try lines(typing: "claude") == ["--settings", AgentHooks.claudeSettings, "--verbose"])
    }

    /// Options the user's files set, which would change how the wrappers
    /// read their arguments.
    @Test func theUsersShellOptionsDoNotChangeTheWrappers() throws {
        try write("setopt ksh_arrays sh_word_split no_unset glob_subst\n", to: ".zshrc")
        #expect(try lines(typing: "claude 'fix the bug'") == ["--settings", AgentHooks.claudeSettings, "fix the bug"])
        #expect(try lines(typing: "codex") == ["-c", AgentHooks.codexConfig])
    }

    @Test func aShellThatIsNotInteractiveGetsNoWrappers() throws {
        #expect(try lines(typing: "claude --continue", interactive: false) == ["--continue"])
    }

    @Test func theUsersFilesLoadFromTheirHome() throws {
        try write("BEAM_TEST_ENV=env\n", to: ".zshenv")
        try write("BEAM_TEST_RC=rc\n", to: ".zshrc")
        #expect(try expanded(#""$BEAM_TEST_ENV" "$BEAM_TEST_RC" "${ZDOTDIR-unset}""#) == ["env", "rc", "unset"])
    }

    @Test func theUsersFilesLoadFromTheirOwnZdotdir() throws {
        let zdotdir = folder.appending(path: "zdotdir")
        try FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        try write("BEAM_TEST_ENV=env\n", to: ".zshenv", in: zdotdir)
        try write("BEAM_TEST_RC=rc\n", to: ".zshrc", in: zdotdir)
        let loaded = try lines(
            typing: #"printf '%s\n' "$BEAM_TEST_ENV" "$BEAM_TEST_RC" "$ZDOTDIR" >"$BEAM_TEST_OUTPUT""#,
            replacing: ["GHOSTTY_ZSH_ZDOTDIR": zdotdir.path])
        #expect(loaded == ["env", "rc", zdotdir.path])
    }

    /// Ghostty's integration, which Beam's hands over to, still loads.
    @Test func ghosttysIntegrationLoadsToo() throws {
        #expect(try expanded(#"${+functions[_ghostty_deferred_init]}"#) == ["1"])
    }

    @Test func whatPointsAtGhosttysIntegrationDoesNotReachTheUsersShell() throws {
        #expect(try expanded(#""${BEAM_GHOSTTY_ZDOTDIR-unset}""#) == ["unset"])
    }
}
