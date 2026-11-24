import BeamCore
import Foundation
import Testing

/// The records are cut down from what Claude Code 2.1.331 writes.
struct ClaudeHistoryTests {
    private let projects = FileManager.default.temporaryDirectory.appending(path: "beam-history-\(UUID().uuidString)")
    private var history: ClaudeHistory { ClaudeHistory(projects: projects) }
    private let modified = Date(timeIntervalSince1970: 1_800_000_000)

    private static let opening = """
        {"type":"mode","mode":"normal","sessionId":"a"}
        {"type":"file-history-snapshot","messageId":"m","snapshot":{},"isSnapshotUpdate":false}
        {"type":"attachment","attachment":{"cwd":"/elsewhere"},"cwd":"/Users/me/app","sessionId":"a"}
        {"type":"user","message":{"role":"user","content":"hello"},"cwd":"/Users/me/app/later","sessionId":"a"}
        """

    private func conversation(head: String = opening, tail: String) -> Conversation? {
        ClaudeHistory.conversation(session: "a", head: Data(head.utf8), tail: Data(tail.utf8), modified: modified)
    }

    /// Writes a session that ran in `folder` to the project folder `project`.
    private func write(
        _ session: String, in project: String, folder: String, title: String, age: TimeInterval = 0,
        filler: Int = 0
    ) throws {
        let directory = projects.appending(path: project)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(session).jsonl")
        let padding = String(
            repeating: #"{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}"# + "\n", count: filler
        )
        let text = """
            {"type":"mode","mode":"normal"}
            {"type":"user","cwd":"\(folder)","message":{"role":"user","content":"hello"}}
            \(padding){"type":"ai-title","aiTitle":"\(title)","sessionId":"\(session)"}

            """
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: modified.addingTimeInterval(-age)], ofItemAtPath: file.path)
    }

    // MARK: A project's folder

    @Test func aProjectFolderIsNamedForItsPathWithOnlyLettersAndDigitsKept() {
        #expect(
            ClaudeHistory.projectPrefix(for: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Deals_2")
                == "-Users-me-Library-Mobile-Documents-com-apple-CloudDocs-Deals-2")
        #expect(ClaudeHistory.projectPrefix(for: "/Users/me/.config") == "-Users-me--config")
    }

    /// Claude Code replaces UTF-16 units, so a character outside the basic
    /// plane leaves two dashes.
    @Test func everyUTF16UnitOutsideASCIILeavesADash() {
        #expect(ClaudeHistory.projectPrefix(for: "/w/café") == "-w-caf-")
        #expect(ClaudeHistory.projectPrefix(for: "/w/🚀") == "-w---")
    }

    /// A long name is cut and ends in a hash Beam does not compute.
    @Test func aLongNameStopsWhereClaudeCodeCutsIt() {
        let path = "/" + String(repeating: "a", count: 300)
        #expect(ClaudeHistory.projectPrefix(for: path) == "-" + String(repeating: "a", count: 199))
    }

    // MARK: One session

    @Test func aSessionRanWhereItsFirstRecordSaysAndTakesItsLatestTitle() {
        let found = conversation(
            tail: """
                {"type":"ai-title","aiTitle":"First title","sessionId":"a"}
                {"type":"last-prompt","lastPrompt":"and then?","leafUuid":"u","sessionId":"a"}
                {"type":"ai-title","aiTitle":"Restore sessions","sessionId":"a"}
                {"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}
                """)
        #expect(
            found
                == Conversation(
                    agent: .claude, session: "a", folder: "/Users/me/app", title: "Restore sessions", modified: modified
                ))
    }

    @Test func aNameTheUserGaveBeatsTheGeneratedOne() {
        let found = conversation(
            tail: """
                {"type":"custom-title","customTitle":"Release day","sessionId":"a"}
                {"type":"ai-title","aiTitle":"Restore sessions","sessionId":"a"}
                """)
        #expect(found?.title == "Release day")
    }

    /// A short or headless session has no title yet. Claude Code wraps
    /// pasted text in tags.
    @Test func anUntitledSessionGoesByItsLastPrompt() {
        let found = conversation(
            tail: #"""
                {"type":"last-prompt","lastPrompt":"\n<pasted_content id=\"e0d5\"> Beam will not open\nsince the update </pasted_content>","sessionId":"a"}
                """#)
        #expect(found?.title == "Beam will not open")
    }

    @Test func aLongPromptIsCut() throws {
        let prompt = String(repeating: "word ", count: 60)
        let found = conversation(tail: #"{"type":"last-prompt","lastPrompt":"\#(prompt)"}"#)
        let title = try #require(found?.title)
        #expect(title.count == 100)
        #expect(title.hasSuffix("…"))
    }

    @Test func aSessionWhereNothingWasSaidIsNoConversation() {
        #expect(conversation(tail: #"{"type":"mode","mode":"normal"}"#) == nil)
        #expect(conversation(tail: #"{"type":"last-prompt","lastPrompt":"  \n "}"#) == nil)
    }

    @Test func aSessionThatNamesNoFolderIsNoConversation() {
        let tail = #"{"type":"ai-title","aiTitle":"Restore sessions"}"#
        #expect(conversation(head: #"{"type":"mode","mode":"normal"}"#, tail: tail) == nil)
    }

    /// The ends of a long file are read, so each may start or stop inside
    /// a record.
    @Test func recordsCutShortAreSkipped() {
        let found = conversation(
            head: Self.opening + "\n" + #"{"type":"user","message":{"content":"cut"#,
            tail: """
                xt":"the end of a record"}]}}
                {"type":"ai-title","aiTitle":"Restore sessions","sessionId":"a"}
                not JSON
                """)
        #expect(found?.title == "Restore sessions")
        #expect(found?.folder == "/Users/me/app")
    }

    // MARK: On disk

    @Test func aFolderListsWhatRanInItAndBelowItNewestFirst() throws {
        defer { try? FileManager.default.removeItem(at: projects) }
        try write("old", in: "-Users-me-app", folder: "/Users/me/app", title: "Old", age: 3600)
        try write("new", in: "-Users-me-app", folder: "/Users/me/app", title: "New", age: 60)
        try write("sub", in: "-Users-me-app-Sources-Core", folder: "/Users/me/app/Sources/Core", title: "Sub", age: 600)
        // Named alike, but beside the folder rather than in it.
        try write("notes", in: "-Users-me-app-notes", folder: "/Users/me/app-notes", title: "Notes")
        try write("space", in: "-Users-me-app-2", folder: "/Users/me/app 2", title: "Space")
        try write("other", in: "-Users-me-site", folder: "/Users/me/site", title: "Other")
        // Not sessions.
        try Data("{}".utf8).write(to: projects.appending(path: "-Users-me-app/notes.txt"))
        try FileManager.default.createDirectory(
            at: projects.appending(path: "-Users-me-app/old/subagents"), withIntermediateDirectories: true)

        let found = history.conversations(in: "/Users/me/app")
        #expect(found.map(\.title) == ["New", "Sub", "Old"])
        #expect(found.map(\.session) == ["new", "sub", "old"])
        #expect(found.map(\.folder) == ["/Users/me/app", "/Users/me/app/Sources/Core", "/Users/me/app"])
        #expect(found.first?.modified == modified.addingTimeInterval(-60))
        #expect(history.conversations(in: "/Users/me/app-notes").map(\.title) == ["Notes"])
    }

    @Test func onlyTheEndsOfALongSessionAreNeeded() throws {
        defer { try? FileManager.default.removeItem(at: projects) }
        // Some 280KB between the folder and the title.
        try write("long", in: "-Users-me-app", folder: "/Users/me/app", title: "Long", filler: 4000)
        #expect(history.conversations(in: "/Users/me/app").map(\.title) == ["Long"])
    }

    /// Claude Code names a project for where its folder really is.
    @Test func aFolderReachedThroughALinkListsWhatRanInItsTarget() throws {
        let manager = FileManager.default
        defer { try? manager.removeItem(at: projects) }
        let real = projects.appending(path: "real")
        let link = projects.appending(path: "link")
        try manager.createDirectory(at: real, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: link, withDestinationURL: real)
        // The temporary folder is itself behind a link, `/var` to `/private/var`.
        let resolved = try #require(realpath(real.path, nil))
        defer { free(resolved) }
        let target = String(cString: resolved)
        try write("linked", in: ClaudeHistory.projectPrefix(for: target), folder: target, title: "Linked")

        #expect(history.conversations(in: link.path).map(\.title) == ["Linked"])
        #expect(history.conversations(in: link.path).map(\.folder) == [target])
    }

    @Test func aFolderWithNoHistoryListsNothing() {
        #expect(history.conversations(in: "/Users/me/app").isEmpty)
    }
}
