import BeamCore
import Foundation
import Testing

struct StateFileTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var file: StateFile { StateFile(url: folder.appendingPathComponent("Beam/state.json")) }

    func makeStore() -> WorkspaceStore {
        var store = WorkspaceStore()
        let two = store.open(folder: "/two")
        store.open(folder: "/one")
        store.setPinned(two, true)
        store.setColor(two, .orange)
        return store
    }

    @Test func noFileLoadsNothing() throws {
        #expect(try file.load() == nil)
    }

    @Test func aSavedStoreLoadsBackIntoAFolderItCreated() throws {
        let store = makeStore()
        try file.save(store)
        #expect(try file.load() == store)

        var changed = store
        changed.showsArchived = true
        try file.save(changed)
        #expect(try file.load() == changed)
    }

    @Test func anUnreadableFileThrowsAndMovesAsideIntact() throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: file.url)
        #expect(throws: (any Error).self) { try file.load() }

        try file.moveAside()
        #expect(try file.load() == nil)
        let aside = file.url.deletingLastPathComponent().appendingPathComponent("state.unreadable.json")
        #expect(try Data(contentsOf: aside) == garbage)
    }

    @Test func aFileFromANewerBeamIsNotRead() throws {
        try file.save(makeStore())
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        json["version"] = 2
        try JSONSerialization.data(withJSONObject: json).write(to: file.url)
        #expect(throws: StateFile.UnsupportedVersion(version: 2)) { try file.load() }
    }
}
