import BeamCore
import Foundation
import Testing

struct SettingsFileTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var file: SettingsFile { SettingsFile(url: folder.appendingPathComponent(".config/beam/config.ghostty")) }

    @Test func aMissingFileIsCreatedWithOnlyComments() throws {
        try file.createIfMissing()
        let contents = try String(contentsOf: file.url, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.hasPrefix("#") })
    }

    @Test func anExistingFileIsLeftAlone() throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mine = Data("font-size = 15\n".utf8)
        try mine.write(to: file.url)
        try file.createIfMissing()
        #expect(try Data(contentsOf: file.url) == mine)
    }

    @Test func theStandardFileSitsBesideGhosttys() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        #expect(SettingsFile.standard.url == home.appendingPathComponent(".config/beam/config.ghostty"))
    }
}
