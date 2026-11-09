import BeamCore
import Testing

struct AgentTests {
    @Test func eachAgentStartsANewSessionWithItsOwnProgram() {
        #expect(Agent.allCases.map(\.command) == ["claude", "codex", "gemini", "kimi"])
    }

    @Test func resumingAnAgentPicksUpItsLastSessionInTheFolder() {
        #expect(Agent.resuming("claude") == "claude --continue")
        #expect(Agent.resuming("codex") == "codex resume --last")
        #expect(Agent.resuming("gemini") == "gemini --resume")
        #expect(Agent.resuming("kimi") == "kimi --continue")
    }

    @Test func resumingTwiceIsTheSameAsOnce() {
        for agent in Agent.allCases {
            #expect(Agent.resuming(Agent.resuming(agent.command)) == agent.resumeCommand)
        }
    }

    @Test func anAgentThatReportedItsSessionResumesExactlyThatOne() {
        #expect(Agent.resuming("claude", session: "00893aaf-19fa") == "claude --resume 00893aaf-19fa")
        #expect(Agent.resuming("claude --resume old", session: "new") == "claude --resume new")
        #expect(Agent.resuming("codex", session: "11111111-2222") == "codex resume 11111111-2222")
        #expect(Agent.resuming("claude", session: nil) == "claude --continue")
        #expect(Agent.resuming("npm run dev", session: "abc") == "npm run dev")
    }

    /// Session IDs come from state.json, which anyone can edit, and are typed
    /// into a shell.
    @Test func aSessionIsQuotedForTheShell() {
        #expect(Agent.resuming("claude", session: "a; rm -rf ~") == #"claude --resume a\;\ rm\ -rf\ ~"#)
    }

    @Test func otherCommandsRunAgainAsTheyWere() {
        #expect(Agent.resuming("npm run dev") == "npm run dev")
        #expect(Agent.resuming("claudette") == "claudette")
        #expect(Agent.resuming("") == "")
    }

    @Test func anAgentIsKnownByItsCommandsFirstWord() {
        #expect(Agent(command: "codex resume --last") == .codex)
        #expect(Agent(command: "kimi") == .kimi)
        #expect(Agent(command: "claudette --continue") == nil)
        #expect(Agent(command: "") == nil)
    }

    @Test func anAgentIsFoundInTheFirstPathEntryThatHasIt() {
        let executables: Set = ["/b/claude", "/c/claude"]
        #expect(Agent.claude.location(onPath: "/a:/b:/c", isExecutable: executables.contains) == "/b/claude")
        #expect(Agent.codex.location(onPath: "/a:/b:/c", isExecutable: executables.contains) == nil)
    }

    @Test func relativePathEntriesAreSkipped() {
        let executables: Set = ["claude", "bin/claude", "/b/claude"]
        #expect(Agent.claude.location(onPath: "::bin:/b", isExecutable: executables.contains) == "/b/claude")
        #expect(Agent.claude.location(onPath: "", isExecutable: executables.contains) == nil)
    }
}
