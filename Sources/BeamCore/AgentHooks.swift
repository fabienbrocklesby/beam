import Foundation

/// How the agents Beam starts report their state: each agent CLI is given
/// hooks that run the `beam` helper, which passes the hook's payload on to
/// beamd, at the pane's `BEAM_SOCKET`, with the pane it came from.
///
/// The hooks ride in on the agent's own command line, so the user's settings
/// files are never edited. Beam types that command line into the user's shell
/// with the definitions left in variables, which keeps what the user sees and
/// what their history keeps short.
public struct AgentHooks: Equatable, Sendable {
    /// The `beam` helper inside Beam.app.
    public let helper: String

    public init(helper: String) {
        self.helper = helper
    }

    /// Variables for a pane's environment: the helper, and each agent's hook
    /// definitions.
    public var environment: [String: String] {
        [
            "BEAM_CLI": helper,
            "BEAM_CLAUDE_SETTINGS": Self.claudeSettings,
            "BEAM_CODEX_HOOKS": Self.codexConfig,
        ]
    }

    /// `command` as Beam types it: an agent that takes hooks gets the
    /// arguments that load them right after its program name, where every
    /// form of its command accepts them.
    public func typed(_ command: String) -> String {
        let arguments: String
        switch Agent(command: command) {
        case .claude: arguments = #"--settings "$BEAM_CLAUDE_SETTINGS""#
        case .codex: arguments = #"-c "$BEAM_CODEX_HOOKS""#
        case .gemini, .kimi, nil: return command
        }
        let words = command.split(separator: " ", maxSplits: 1)
        return ([words[0], Substring(arguments)] + words.dropFirst()).joined(separator: " ")
    }

    /// Every hook runs the helper through `$BEAM_CLI`, so a definition is the
    /// same wherever Beam.app lives. Codex asks the user to trust each hook
    /// definition once, and would ask again if it changed.
    private static func handler(_ agent: Agent) -> String { #""$BEAM_CLI" hook \#(agent.rawValue)"# }

    /// For `claude --settings`, which adds these hooks to the user's own.
    /// Matched to `AgentHook`: every event it reads from Claude Code.
    public static let claudeSettings: String = {
        let events = [
            "SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "PostToolUseFailure",
            "Notification", "Stop", "StopFailure", "SessionEnd",
        ]
        let command = handler(.claude).replacing("\"", with: #"\""#)
        let group = #"[{"hooks":[{"type":"command","command":"\#(command)"}]}]"#
        return #"{"hooks":{"# + events.map { #""\#($0)":\#(group)"# }.joined(separator: ",") + "}}"
    }()

    /// For `codex -c`, which reads the value as TOML. Codex keeps the user's
    /// own hooks, and their trust, beside a `hooks` table set this way.
    /// Matched to `AgentHook`: every event it reads from Codex.
    public static let codexConfig: String = {
        let events = ["PermissionRequest", "PostToolUse", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]
        let command = handler(.codex).replacing("\"", with: #"\""#)
        let group = #"[{hooks=[{type="command",command="\#(command)"}]}]"#
        return "hooks={" + events.map { "\($0)=\(group)" }.joined(separator: ",") + "}"
    }()
}
