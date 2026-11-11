import BeamCore
import Foundation
import Testing

/// Payloads follow the shapes in Claude Code's and Codex's hook references,
/// trimmed to the fields that matter plus a few that do not.
struct AgentHookTests {
    private let pane = Pane.ID()

    private func event(_ json: String, _ agent: Agent = .claude) -> AgentReport.Event? {
        AgentHook.report(from: Data(json.utf8), pane: pane, agent: agent)?.event
    }

    private func files(_ json: String, _ agent: Agent = .claude) -> AgentReport.Files? {
        AgentHook.report(from: Data(json.utf8), pane: pane, agent: agent)?.files
    }

    @Test func aStartedOrResumedSessionReportsItsID() {
        #expect(
            event(
                #"{"session_id":"00893aaf-19fa-41d2-8238-13269b9b3ca0","hook_event_name":"SessionStart","source":"startup","cwd":"/tmp"}"#
            ) == .started(session: "00893aaf-19fa-41d2-8238-13269b9b3ca0"))
        #expect(
            event(
                #"{"session_id":"11111111-2222-7333-8444-555555555555","hook_event_name":"SessionStart","source":"resume"}"#,
                .codex) == .started(session: "11111111-2222-7333-8444-555555555555"))
    }

    @Test func compactingKeepsTheSessionAndItsState() {
        #expect(event(#"{"session_id":"abc","hook_event_name":"SessionStart","source":"compact"}"#) == nil)
    }

    /// The ID is typed into a shell when the pane resumes, so only the
    /// characters session IDs are made of get through.
    @Test func aSessionIDThatCouldNotBeTypedSafelyIsDropped() {
        #expect(
            event(#"{"session_id":"abc; rm -rf ~","hook_event_name":"SessionStart","source":"startup"}"#)
                == .started(session: nil))
        #expect(event(#"{"hook_event_name":"SessionStart","source":"startup"}"#) == .started(session: nil))
        #expect(event(#"{"session_id":"","hook_event_name":"SessionStart"}"#) == .started(session: nil))
    }

    @Test func promptsAndToolResultsMeanWorking() {
        #expect(
            event(#"{"session_id":"abc","hook_event_name":"UserPromptSubmit","prompt":"Fix the build"}"#) == .working)
        #expect(
            event(#"{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"stdout":""}}"#) == .working)
        #expect(
            event(#"{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"Exit code 1"}"#) == .working)
        #expect(event(#"{"hook_event_name":"PostToolUse","tool_name":"apply_patch"}"#, .codex) == .working)
    }

    @Test func aPermissionRequestWaitsOnTheUser() {
        #expect(
            event(
                #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}"#
            )
                == .waiting(message: "Needs your permission to use Bash"))
        #expect(event(#"{"hook_event_name":"PermissionRequest"}"#) == .waiting(message: "Needs your permission"))
    }

    @Test func notificationsThatNeedTheUserWaitWithTheirMessage() {
        #expect(
            event(
                #"{"hook_event_name":"Notification","message":"Claude needs your permission","title":"Permission needed","notification_type":"permission_prompt"}"#
            ) == .waiting(message: "Claude needs your permission"))
        #expect(
            event(
                #"{"hook_event_name":"Notification","message":"Fill in the form","notification_type":"elicitation_dialog"}"#
            )
                == .waiting(message: "Fill in the form"))
        #expect(
            event(#"{"hook_event_name":"Notification","notification_type":"elicitation_url_dialog"}"#)
                == .waiting(message: "Needs your input"))
    }

    @Test func anIdlePromptReportsIdleAndOtherNotificationsNothing() {
        #expect(
            event(
                #"{"hook_event_name":"Notification","message":"Claude is waiting","notification_type":"idle_prompt"}"#)
                == .idle)
        #expect(event(#"{"hook_event_name":"Notification","notification_type":"auth_success"}"#) == nil)
        #expect(event(#"{"hook_event_name":"Notification","message":"Hi"}"#) == nil)
    }

    @Test func stoppingIsDoneWithTheFirstLineOfTheReply() {
        #expect(
            event(
                #"{"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"\n  Fixed the build.  \nDetails follow."}"#
            ) == .done(message: "Fixed the build."))
        #expect(event(#"{"hook_event_name":"Stop","last_assistant_message":null}"#, .codex) == .done(message: nil))
        #expect(event(#"{"hook_event_name":"Stop","last_assistant_message":" \n "}"#) == .done(message: nil))
    }

    @Test func aLongReplyIsCutToFitANotification() {
        let reply = String(repeating: "word ", count: 100)
        guard case .done(let message?) = event(#"{"hook_event_name":"Stop","last_assistant_message":"\#(reply)"}"#)
        else {
            Issue.record("expected a message")
            return
        }
        #expect(message.count == 200)
        #expect(message.hasSuffix("…"))
    }

    @Test func aFailedTurnIsDoneWithItsError() {
        #expect(
            event(
                #"{"hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"API Error: Rate limit reached"}"#
            ) == .done(message: "API Error: Rate limit reached"))
        #expect(event(#"{"hook_event_name":"StopFailure","error":"overloaded"}"#) == .done(message: "overloaded"))
    }

    @Test func anEndedSessionReportsEnded() {
        #expect(event(#"{"session_id":"abc","hook_event_name":"SessionEnd","reason":"prompt_input_exit"}"#) == .ended)
    }

    @Test func otherEventsAndBadInputReportNothing() {
        #expect(event(#"{"hook_event_name":"PreToolUse","tool_name":"Bash"}"#) == nil)
        #expect(event(#"{"hook_event_name":"SubagentStop"}"#) == nil)
        #expect(event(#"{"session_id":"abc"}"#) == nil)
        #expect(event("not json") == nil)
        #expect(event("") == nil)
    }

    @Test func theReportIsForThePaneAndAgentGiven() {
        let report = AgentHook.report(from: Data(#"{"hook_event_name":"Stop"}"#.utf8), pane: pane, agent: .codex)
        #expect(report == AgentReport(pane: pane, agent: .codex, event: .done(message: nil)))
    }

    // MARK: Files

    @Test func stoppingNamesTheFilesTheReplyMentions() {
        #expect(
            files(
                #"{"hook_event_name":"Stop","cwd":"/Users/me/Code/beam","last_assistant_message":"Saved `shot.png` and ![chart](out/chart.svg)."}"#
            ) == AgentReport.Files(directory: "/Users/me/Code/beam", names: ["shot.png", "out/chart.svg"]))
        #expect(
            files(#"{"hook_event_name":"Stop","cwd":"/r","last_assistant_message":"Created `notes.txt`."}"#, .codex)
                == AgentReport.Files(directory: "/r", names: ["notes.txt"]))
    }

    @Test func aReplyThatMentionsNoFilesNamesNone() {
        #expect(files(#"{"hook_event_name":"Stop","cwd":"/r","last_assistant_message":"All done."}"#) == nil)
        #expect(files(#"{"hook_event_name":"Stop","cwd":"/r"}"#) == nil)
    }

    /// Shapes from a real Claude Code session.
    @Test func aToolResultNamesTheFilesTheToolWasGiven() {
        #expect(
            files(
                #"{"hook_event_name":"PostToolUse","cwd":"/r","tool_name":"Write","tool_input":{"file_path":"/r/notes.txt","content":"hello"},"tool_response":{"type":"create"}}"#
            ) == AgentReport.Files(directory: "/r", names: ["/r/notes.txt"]))
        #expect(
            files(
                #"{"hook_event_name":"PostToolUse","cwd":"/r","tool_name":"Bash","tool_input":{"command":"mkdir -p shots && printf 'x' > shots/pic.png","description":"Write pic.png"}}"#
            ) == AgentReport.Files(directory: "/r", names: ["shots/pic.png"]))
        #expect(
            files(
                #"{"hook_event_name":"PostToolUse","cwd":"/r","tool_name":"NotebookEdit","tool_input":{"notebook_path":"/r/a.ipynb"}}"#
            ) == AgentReport.Files(directory: "/r", names: ["/r/a.ipynb"]))
    }

    /// The shape from a real Codex session: `apply_patch` puts its patch in
    /// `command`.
    @Test func aCodexPatchNamesTheFilesItEdits() {
        let patch = #"*** Begin Patch\n*** Add File: diagram.svg\n+<svg/>\n*** End Patch"#
        #expect(
            files(
                #"{"hook_event_name":"PostToolUse","cwd":"/r","tool_name":"apply_patch","tool_input":{"command":"\#(patch)"}}"#,
                .codex) == AgentReport.Files(directory: "/r", names: ["diagram.svg"]))
    }

    /// A tool input of some other shape must never cost the report itself.
    @Test func anUnexpectedToolInputStillReportsWorking() {
        for input in [#""a string""#, #"{"command":["ls","-la"]}"#, #"{"file_path":7}"#, "null"] {
            let json = #"{"hook_event_name":"PostToolUse","cwd":"/r","tool_name":"Bash","tool_input":\#(input)}"#
            #expect(event(json) == .working, "\(input)")
            #expect(files(json) == nil, "\(input)")
        }
    }

    @Test func aFailedToolNamesNoFiles() {
        #expect(
            files(
                #"{"hook_event_name":"PostToolUseFailure","cwd":"/r","tool_name":"Write","tool_input":{"file_path":"/r/a.png"}}"#
            ) == nil)
    }

    /// Enough for any reply; a payload can be any size.
    @Test func aReportNamesAtMostThirtyTwoFiles() {
        let reply = (1...40).map { "f\($0).png" }.joined(separator: " ")
        let named = files(#"{"hook_event_name":"Stop","last_assistant_message":"\#(reply)"}"#)
        #expect(named?.names.count == 32)
        #expect(named?.names.first == "f1.png")
        #expect(named?.directory == nil)
    }
}
