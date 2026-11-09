import BeamCore
import Foundation
import Testing

struct AgentHooksTests {
    let hooks = AgentHooks(helper: "/Applications/Beam.app/Contents/Helpers/beam")

    @Test func panesLearnTheHelperAndHowEachAgentLoadsItsHooks() {
        let environment = hooks.environment
        #expect(environment["BEAM_CLI"] == "/Applications/Beam.app/Contents/Helpers/beam")
        #expect(environment["BEAM_CLAUDE_SETTINGS"] == AgentHooks.claudeSettings)
        #expect(environment["BEAM_CODEX_HOOKS"] == AgentHooks.codexConfig)
    }

    @Test func agentsThatTakeHooksGetThemRightAfterTheirProgramName() {
        #expect(hooks.typed("claude") == #"claude --settings "$BEAM_CLAUDE_SETTINGS""#)
        #expect(hooks.typed("claude --resume abc") == #"claude --settings "$BEAM_CLAUDE_SETTINGS" --resume abc"#)
        #expect(hooks.typed("codex") == #"codex -c "$BEAM_CODEX_HOOKS""#)
        #expect(hooks.typed("codex resume --last") == #"codex -c "$BEAM_CODEX_HOOKS" resume --last"#)
    }

    @Test func otherCommandsAreTypedAsTheyAre() {
        #expect(hooks.typed("gemini --resume") == "gemini --resume")
        #expect(hooks.typed("kimi") == "kimi")
        #expect(hooks.typed("npm run dev") == "npm run dev")
        #expect(hooks.typed("claudette") == "claudette")
    }

    /// Every hook runs the helper through the variable, so the definition is
    /// the same wherever Beam.app lives: Codex asks the user to trust a hook
    /// once per definition.
    @Test func claudeSettingsRunTheHelperOnEveryEventBeamReads() throws {
        let settings = try JSONDecoder().decode(ClaudeSettings.self, from: Data(AgentHooks.claudeSettings.utf8))
        #expect(
            settings.hooks.keys.sorted() == [
                "Notification", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "SessionEnd",
                "SessionStart", "Stop", "StopFailure", "UserPromptSubmit",
            ])
        for groups in settings.hooks.values {
            #expect(groups.count == 1)
            #expect(groups.first?.hooks == [.init(type: "command", command: #""$BEAM_CLI" hook claude"#)])
        }
    }

    @Test func codexConfigIsOneHooksTableForItsConfigFlag() {
        let group = #"[{hooks=[{type="command",command="\"$BEAM_CLI\" hook codex"}]}]"#
        let events = ["PermissionRequest", "PostToolUse", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]
        #expect(AgentHooks.codexConfig == "hooks={" + events.map { "\($0)=\(group)" }.joined(separator: ",") + "}")
    }

    private struct ClaudeSettings: Decodable {
        struct Group: Decodable {
            let hooks: [Handler]
        }
        struct Handler: Decodable, Equatable {
            let type: String
            let command: String
        }
        let hooks: [String: [Group]]
    }
}
