import BeamCore
import Testing

struct WorkspaceTests {
    let workspace = Workspace(folder: "/Users/me/Code/beam")

    @Test func itsOwnFolderGoesByItsName() {
        #expect(workspace.relativeName(of: "/Users/me/Code/beam") == "beam")
        #expect(workspace.relativeName(of: "/Users/me/Code/beam/") == "beam")
    }

    @Test func aFolderInsideItGoesByThePathFromItsName() {
        var renamed = workspace
        renamed.name = "Beam app"
        #expect(workspace.relativeName(of: "/Users/me/Code/beam/Sources/Beam") == "beam/Sources/Beam")
        #expect(renamed.relativeName(of: "/Users/me/Code/beam/Sources") == "Beam app/Sources")
    }

    @Test func aFolderOutsideItHasNoRelativeName() {
        #expect(workspace.relativeName(of: "/Users/me/Code/beamd") == nil)
        #expect(workspace.relativeName(of: "/Users/me/Code") == nil)
        #expect(workspace.relativeName(of: "/tmp") == nil)
    }
}
