import BeamCore
import Foundation
import Testing

/// Against a made-up disk, so each test says exactly which files exist.
struct FileResolverTests {
    private let repository = "/Users/me/Code/beam"
    private let scratchpad = "/tmp/session/scratchpad"

    private func resolver(_ files: Set<String>) -> FileResolver {
        FileResolver { files.contains($0) }
    }

    @Test func anAbsolutePathThatExistsIsItself() {
        let resolver = resolver(["/Users/me/shot.png"])
        #expect(resolver.path(for: "/Users/me/shot.png", directory: nil, touched: []) == "/Users/me/shot.png")
        #expect(resolver.path(for: "/Users/me/Code/../shot.png", directory: nil, touched: []) == "/Users/me/shot.png")
    }

    @Test func aRelativePathStartsFromTheDirectory() {
        let resolver = resolver([repository + "/Sources/Beam/App/main.swift", "/Users/me/notes.md"])
        #expect(
            resolver.path(for: "Sources/Beam/App/main.swift", directory: repository, touched: [])
                == repository + "/Sources/Beam/App/main.swift")
        #expect(resolver.path(for: "../../notes.md", directory: repository, touched: []) == "/Users/me/notes.md")
        #expect(resolver.path(for: "./Sources/Beam/App/main.swift", directory: repository, touched: []) != nil)
    }

    /// The agent wrote the file this turn, somewhere other than where it
    /// works, and named it by its name alone.
    @Test func aBareNameIsAFileTouchedThisTurn() {
        let shot = scratchpad + "/shot.png"
        let resolver = resolver([shot])
        #expect(resolver.path(for: "shot.png", directory: repository, touched: [shot]) == shot)
    }

    @Test func aPartialPathIsTheEndOfAFileTouchedThisTurn() {
        let shot = scratchpad + "/shots/dark.png"
        let resolver = resolver([shot])
        #expect(resolver.path(for: "shots/dark.png", directory: repository, touched: [shot]) == shot)
        // Only whole names count: `ark.png` is not `dark.png`.
        #expect(resolver.path(for: "ark.png", directory: repository, touched: [shot]) == nil)
    }

    /// The scratchpad case: a Bash command wrote the screenshot next to a
    /// file a tool named.
    @Test func aBareNameIsInTheFolderOfAFileTouchedThisTurn() {
        let shot = scratchpad + "/shot-dark.png"
        let resolver = resolver([scratchpad + "/notes.md", shot])
        #expect(
            resolver.path(for: "shot-dark.png", directory: repository, touched: [scratchpad + "/notes.md"]) == shot)
    }

    @Test func aFileTouchedThisTurnWinsOverOneInTheDirectory() {
        let touched = repository + "/docs/README.md"
        let resolver = resolver([repository + "/README.md", touched])
        #expect(resolver.path(for: "README.md", directory: repository, touched: [touched]) == touched)
    }

    @Test func aFileInTheDirectoryWinsOverOneBesideATouchedFile() {
        let resolver = resolver([repository + "/README.md", scratchpad + "/README.md", scratchpad + "/notes.md"])
        #expect(
            resolver.path(for: "README.md", directory: repository, touched: [scratchpad + "/notes.md"])
                == repository + "/README.md")
    }

    /// So no chip or link ever points at nothing.
    @Test func whatDoesNotExistIsDropped() {
        let resolver = resolver([repository + "/README.md"])
        #expect(resolver.path(for: "/Users/me/gone.png", directory: repository, touched: []) == nil)
        #expect(resolver.path(for: "gone.png", directory: repository, touched: [scratchpad + "/notes.md"]) == nil)
        // A file the agent touched, then deleted.
        #expect(resolver.path(for: "notes.md", directory: nil, touched: [scratchpad + "/notes.md"]) == nil)
    }

    @Test func withoutADirectoryARelativePathNeedsATouchedFile() {
        let resolver = resolver([repository + "/README.md"])
        #expect(resolver.path(for: "README.md", directory: nil, touched: []) == nil)
    }

    @Test func namesResolveEachOnceInOrderWithoutWebAddressesOrMissingFiles() {
        let shot = scratchpad + "/shot.png"
        let resolver = resolver([shot, "/Users/me/a.png", repository + "/Sources/main.swift"])
        let names = [
            "shot.png", "https://example.com/a.png", "~/a.png", "Sources/main.swift:12", shot, "missing.png",
        ]
        #expect(
            resolver.paths(for: names, directory: repository, touched: [shot], home: "/Users/me") == [
                shot, "/Users/me/a.png", repository + "/Sources/main.swift",
            ])
    }
}
