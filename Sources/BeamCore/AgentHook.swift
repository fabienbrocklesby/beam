import Foundation

/// Reads the JSON an agent CLI passes its hooks on stdin. Claude Code and
/// Codex share the event names and fields Beam reads; only Claude Code sends
/// `Notification`, `PostToolUseFailure` and `StopFailure`.
public enum AgentHook {
    private struct Payload: Decodable {
        let hookEventName: String
        let sessionId: String?
        let source: String?
        let toolName: String?
        let message: String?
        let notificationType: String?
        let lastAssistantMessage: String?
        let error: String?
    }

    /// Notification types that mean the agent is blocked on the user.
    private static let waitingNotifications: Set = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// Longest message a report carries: enough for a notification's body.
    private static let messageLimit = 200

    /// What `payload` reports, or nil for events that change nothing and for
    /// input that is not a hook payload.
    public static func event(from payload: Data, agent: Agent) -> AgentReport.Event? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: payload) else { return nil }

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
