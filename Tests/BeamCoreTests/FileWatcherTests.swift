import BeamCore
import Foundation
import Testing

/// Each writer the spike found agents and editors use, against a file in a
/// temporary folder. A writer in place truncates before it writes, so a
/// callback may see the file empty first; the checks wait for the content
/// they expect. The watcher calls once as it starts, which `watch` takes.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FileWatcherTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var file: URL { folder.appendingPathComponent("plan.md") }

    /// Starts watching `file`, which holds "one" unless `exists` is false.
    /// Each change arrives as what the file held when the watcher called
    /// back, nil when it was gone.
    private func watch(exists: Bool = true) async throws -> (FileWatcher, AsyncStream<String?>) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if exists { try write("one") }
        let (changes, continuation) = AsyncStream.makeStream(of: String?.self)
        let file = file
        let watcher = FileWatcher(path: file.path) {
            continuation.yield(try? String(contentsOf: file, encoding: .utf8))
        }
        #expect(await wait(for: exists ? "one" : nil, in: changes))
        return (watcher, changes)
    }

    /// Writes in place, as Codex's apply_patch, vim and a shell redirect do.
    private func write(_ text: String) throws {
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        let bytes = Array(text.utf8)
        try #require(Darwin.write(descriptor, bytes, bytes.count) == bytes.count)
    }

    /// Replaces the file, as Claude Code's Write and Edit and NSDocument do.
    private func replace(_ text: String) throws {
        try Data(text.utf8).write(to: file, options: .atomic)
    }

    /// Reads changes until one shows `expected`.
    private func wait(for expected: String?, in changes: AsyncStream<String?>) async -> Bool {
        var next = changes.makeAsyncIterator()
        while let change = await next.next() {
            if change == expected { return true }
        }
        return false
    }

    @Test func aWriteInPlace() async throws {
        let (watcher, changes) = try await watch()
        try write("two")
        #expect(await wait(for: "two", in: changes))
        _ = watcher
    }

    @Test func aReplacementAndThenAWriteToTheNewFile() async throws {
        let (watcher, changes) = try await watch()
        try replace("two")
        #expect(await wait(for: "two", in: changes))
        try write("three")
        #expect(await wait(for: "three", in: changes))
        _ = watcher
    }

    @Test func aDeletionAndTheFileComingBack() async throws {
        let (watcher, changes) = try await watch()
        try FileManager.default.removeItem(at: file)
        #expect(await wait(for: nil, in: changes))
        try write("back")
        #expect(await wait(for: "back", in: changes))
        try write("again")
        #expect(await wait(for: "again", in: changes))
        _ = watcher
    }

    @Test func aFileThatDoesNotExistYet() async throws {
        let (watcher, changes) = try await watch(exists: false)
        try write("new")
        #expect(await wait(for: "new", in: changes))
        _ = watcher
    }

    @Test func aRenameAway() async throws {
        let (watcher, changes) = try await watch()
        try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent("moved.md"))
        #expect(await wait(for: nil, in: changes))
        _ = watcher
    }

    /// Neither another file in the folder nor a permission change is a
    /// change to the file, so the first call is for the replacement.
    @Test func otherChangesInTheFolderAreNotReported() async throws {
        let (watcher, changes) = try await watch()
        try Data("other".utf8).write(to: folder.appendingPathComponent("other.md"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try replace("two")
        var next = changes.makeAsyncIterator()
        let change = await next.next()
        #expect(change == "two")
        _ = watcher
    }
}
