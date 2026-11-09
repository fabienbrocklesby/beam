import BeamCore
import Foundation
import Testing

struct GitHeadTests {
    // MARK: Naming

    @Test func aBranchIsNamedWithoutItsRefsPrefix() {
        #expect(GitHead.name(fromContents: "ref: refs/heads/main\n") == "main")
        #expect(GitHead.name(fromContents: "ref: refs/heads/feature/split-zoom") == "feature/split-zoom")
    }

    @Test func aRefOutsideBranchesKeepsItsFullName() {
        #expect(GitHead.name(fromContents: "ref: refs/remotes/origin/main\n") == "refs/remotes/origin/main")
    }

    @Test func aDetachedHeadIsNamedByItsShortCommit() {
        #expect(GitHead.name(fromContents: "67a3ab3c0f1e2d4b5a69788796a5b4c3d2e1f0a9\n") == "67a3ab3")
    }

    @Test func anythingElseHasNoName() {
        #expect(GitHead.name(fromContents: "") == nil)
        #expect(GitHead.name(fromContents: "not a head\n") == nil)
        #expect(GitHead.name(fromContents: "ref: \n") == nil)
    }

    // MARK: Finding HEAD

    @Test func aRepositoryKeepsHeadInItsGitDirectory() throws {
        let root = try temporaryFolder()
        try makeDirectory(root + "/.git")
        #expect(GitHead.file(containing: root) == root + "/.git/HEAD")
    }

    @Test func aSubfolderUsesTheNearestEnclosingRepository() throws {
        let root = try temporaryFolder()
        try makeDirectory(root + "/.git")
        try makeDirectory(root + "/Sources/Beam")
        #expect(GitHead.file(containing: root + "/Sources/Beam") == root + "/.git/HEAD")
    }

    @Test func aWorktreeFollowsItsGitdirFile() throws {
        let root = try temporaryFolder()
        try makeDirectory(root + "/main/.git/worktrees/feature")
        try makeDirectory(root + "/feature")
        try write("gitdir: \(root)/main/.git/worktrees/feature\n", to: root + "/feature/.git")
        #expect(GitHead.file(containing: root + "/feature") == root + "/main/.git/worktrees/feature/HEAD")
    }

    @Test func aRelativeGitdirResolvesFromItsFolder() throws {
        let root = try temporaryFolder()
        try makeDirectory(root + "/.git/modules/lib")
        try makeDirectory(root + "/lib")
        try write("gitdir: ../.git/modules/lib\n", to: root + "/lib/.git")
        #expect(GitHead.file(containing: root + "/lib") == root + "/.git/modules/lib/HEAD")
    }

    @Test func aFolderOutsideAnyRepositoryHasNoHead() throws {
        #expect(GitHead.file(containing: try temporaryFolder()) == nil)
    }

    @Test func theNameIsReadFromTheHeadFile() throws {
        let root = try temporaryFolder()
        try makeDirectory(root + "/.git")
        try write("ref: refs/heads/main\n", to: root + "/.git/HEAD")
        #expect(GitHead.name(ofFile: root + "/.git/HEAD") == "main")
        #expect(GitHead.name(ofFile: root + "/.git/missing") == nil)
    }

    // MARK: Fixtures

    private func temporaryFolder() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // The temporary directory is reached through a symlink (/var to /private/var).
        return url.resolvingSymlinksInPath().path
    }

    private func makeDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func write(_ contents: String, to path: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
