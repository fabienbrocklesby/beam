import Foundation

/// Reads the JSON an agent CLI passes its hooks on stdin. Claude Code and
/// Codex share the event names and fields Beam reads; only Claude Code sends
/// `Notification`, `PostToolUseFailure` and `StopFailure`. Their tools
/// differ: Codex edits files with `apply_patch`, whose patch names them.
public enum AgentHook {
    private struct Payload: Decodable {
        let hookEventName: String
        let sessionId: String?
        let source: String?
        let cwd: String?
        let toolName: String?
        let toolInput: ToolInput?
        let message: String?
        let notificationType: String?
        let lastAssistantMessage: String?
        let error: String?
    }

    /// The fields of a tool's input that name files. Each tool has its own
    /// shape, so a field of another type reads as absent rather than failing
    /// the payload and the report with it.
    private struct ToolInput: Decodable {
        var filePath: String?
        var notebookPath: String?
        var command: String?

        private enum CodingKeys: String, CodingKey {
            case filePath, notebookPath, command
        }

        init(from decoder: any Decoder) {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            filePath = try? container?.decodeIfPresent(String.self, forKey: .filePath)
            notebookPath = try? container?.decodeIfPresent(String.self, forKey: .notebookPath)
            command = try? container?.decodeIfPresent(String.self, forKey: .command)
        }

        /// A shell command's words, or the files an `apply_patch` patch edits.
        func names(tool: String?) -> [String] {
            var names = [filePath, notebookPath].compactMap(\.self)
            if let command {
                names += tool == "apply_patch" ? FileMention.names(inPatch: command) : FileMention.names(in: command)
            }
            return names
        }
    }

    /// Notification types that mean the agent is blocked on the user.
    private static let waitingNotifications: Set = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// Longest message a report carries: enough for a notification's body.
    private static let messageLimit = 200
    /// Most files a report names: plenty for a reply, whatever the size of
    /// the payload.
    private static let filesLimit = 32

    /// What `payload` from `agent` in `pane` reports, or nil for events that
    /// change nothing and for input that is not a hook payload.
    public static func report(from payload: Data, pane: Pane.ID, agent: Agent) -> AgentReport? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: payload), let event = event(of: payload) else {
            return nil
        }
        return AgentReport(pane: pane, agent: agent, event: event, files: files(of: payload))
    }

    private static func event(of payload: Payload) -> AgentReport.Event? {
        switch payload.hookEventName {
        case "SessionStart":
            // Compacting keeps the session, often in the middle of a turn.
            guard payload.source != "compact" else { return nil }
            return .started(session: payload.sessionId.flatMap(typeable))
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure":
            // A tool result also means a permission prompt was answered.
            return .working
        case "PermissionRequest":
            let tool = payload.toolName.map { " to use \($0)" } ?? ""
            return .waiting(message: "Needs your permission" + tool)
        case "Notification":
            if payload.notificationType == "idle_prompt" { return .idle }
            guard let type = payload.notificationType, waitingNotifications.contains(type) else { return nil }
            return .waiting(message: payload.message.flatMap(summary) ?? "Needs your input")
        case "Stop":
            return .done(message: payload.lastAssistantMessage.flatMap(summary))
        case "StopFailure":
            return .done(message: (payload.lastAssistantMessage ?? payload.error).flatMap(summary))
        case "SessionEnd":
            return .ended
        default:
            return nil
        }
    }

    /// What a tool result's input or a finished turn's reply named.
    private static func files(of payload: Payload) -> AgentReport.Files? {
        let names: [String]
        switch payload.hookEventName {
        case "PostToolUse": names = payload.toolInput?.names(tool: payload.toolName) ?? []
        case "Stop": names = payload.lastAssistantMessage.map(FileMention.names(in:)) ?? []
        default: names = []
        }
        guard !names.isEmpty else { return nil }
        return AgentReport.Files(directory: payload.cwd, names: Array(names.prefix(filesLimit)))
    }

    /// `session` when it is made only of what session IDs are made of, so it
    /// can be typed into a shell to resume the session.
    private static func typeable(_ session: String) -> String? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !session.isEmpty, session.count <= 128, session.allSatisfy(allowed.contains) else { return nil }
        return session
    }

    /// The first line of `text` with any text, cut to `messageLimit`.
    private static func summary(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count <= messageLimit ? line : line.prefix(messageLimit - 1) + "…"
    }
}
