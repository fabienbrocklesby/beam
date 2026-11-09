import BeamCore
import Foundation
import Testing

/// Payloads follow the shapes in Claude Code's and Codex's hook references,
/// trimmed to the fields that matter plus a few that do not.
struct AgentHookTests {
    private func event(_ json: String, _ agent: Agent = .claude) -> AgentReport.Event? {
        AgentHook.event(from: Data(json.utf8), agent: agent)
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
}
