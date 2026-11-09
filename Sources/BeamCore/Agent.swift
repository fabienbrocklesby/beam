import Foundation

/// A coding agent CLI the launcher can start in a pane.
public enum Agent: String, CaseIterable, Codable, Sendable {
    case claude, codex, gemini, kimi

    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .kimi: "Kimi"
        }
    }

    /// The program's name on `PATH`, which on its own starts a new session.
    public var command: String { rawValue }

    /// Picks up the agent's most recent session in the current directory.
    public var resumeCommand: String {
        switch self {
        case .claude: "claude --continue"
        case .codex: "codex resume --last"
        case .gemini: "gemini --resume"
        case .kimi: "kimi --continue"
        }
    }

    /// The agent `command` runs, judged by its first word.
    public init?(command: String) {
        guard let program = command.split(separator: " ", maxSplits: 1).first else { return nil }
        self.init(rawValue: String(program))
    }

    /// Picks up exactly `session`, for the agents whose hooks report one.
    public func resumeCommand(session: String) -> String? {
        switch self {
        case .claude: "claude --resume \(Shell.escape(session))"
        case .codex: "codex resume \(Shell.escape(session))"
        case .gemini, .kimi: nil
        }
    }

    /// What a pane that was running `command` when Beam quit runs when it
    /// starts again: an agent's resume form, so its conversation carries on,
    /// or any other command as it was. `session` is the one the agent last
    /// reported, which beats the folder's most recent when there are two.
    public static func resuming(_ command: String, session: String? = nil) -> String {
        guard let agent = Agent(command: command) else { return command }
        return session.flatMap(agent.resumeCommand(session:)) ?? agent.resumeCommand
    }

    /// Where a shell with `path` as its `PATH` finds the agent, or nil if it
    /// would not. Relative entries are skipped: a pane's shell resolves them
    /// against its own directory, which Beam cannot know in advance.
    public func location(onPath path: String, isExecutable: (String) -> Bool) -> String? {
        path.split(separator: ":")
            .lazy
            .filter { $0.hasPrefix("/") }
            .map { (String($0) as NSString).appendingPathComponent(self.command) }
            .first(where: isExecutable)
    }
}
