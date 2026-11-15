import BeamCore
import CoreGraphics
import Foundation
import Testing

/// Document panes: the viewer a click fills, and the workspace a file opened
/// from Finder gets.
struct WorkspaceStoreDocumentTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// A workspace in `/w` with its one shell.
    func makeStore() throws -> (store: WorkspaceStore, id: Workspace.ID, shell: Pane.ID) {
        var store = WorkspaceStore()
        let id = store.open(folder: "/w")
        return (store, id, try #require(store.workspace(id)?.focusedPane))
    }

    func frame(of pane: Pane.ID, in store: WorkspaceStore) -> CGRect? {
        store.workspaceID(containing: pane).flatMap(store.workspace)?.tree
            .layout(in: bounds, dividerThickness: 0).frames[pane]
    }

    // MARK: The viewer

    @Test func aFileOpensInAColumnOnTheRightAndFocusStaysInTheTerminal() throws {
        var (store, id, shell) = try makeStore()
        let shown = store.showDocument("/w/plan.md", from: shell)
        let viewer = try #require(shown)
        let workspace = try #require(store.workspace(id))
        #expect(workspace.tree.panes.map(\.id) == [shell, viewer])
        #expect(workspace.tree.pane(viewer)?.document == "/w/plan.md")
        #expect(workspace.tree.pane(viewer)?.workingDirectory == nil)
        #expect(workspace.viewer == viewer)
        #expect(workspace.focusedPane == shell)
        let column = try #require(frame(of: viewer, in: store))
        #expect(column.height == bounds.height)
        #expect(abs(column.width - bounds.width / 2) <= 1)
    }

    @Test func besideSeveralPanesTheColumnTakesFortyPercent() throws {
        var (store, id, shell) = try makeStore()
        store.openPane(running: "claude", in: id, bounds: bounds)
        store.focus(shell)
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        let column = try #require(frame(of: viewer, in: store))
        #expect(column.height == bounds.height)
        #expect(abs(column.width - bounds.width * 0.4) <= 1)
        #expect(store.workspace(id)?.focusedPane == shell)
    }

    @Test func theNextFileReusesTheViewer() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        let shown = store.showDocument("/w/notes.md", from: shell)

        #expect(shown == viewer)
        let workspace = try #require(store.workspace(id))
        #expect(workspace.tree.panes.count == 2)
        #expect(workspace.tree.pane(viewer)?.document == "/w/notes.md")
    }

    @Test func theFileAlreadyShownIsLeftAlone() throws {
        var (store, _, shell) = try makeStore()
        let viewer = store.showDocument("/w/plan.md", from: shell)
        let before = store
        let shown = store.showDocument("/w/plan.md", from: shell)

        #expect(shown == viewer)
        #expect(store == before)
    }

    /// A relative link clicked in a Markdown file.
    @Test func aLinkInTheViewerOpensInTheViewer() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/README.md", from: shell)

        let viewer = try #require(openedViewer)
        let shown = store.showDocument("/w/docs/PLAN.md", from: viewer)

        #expect(shown == viewer)
        #expect(store.workspace(id)?.tree.pane(viewer)?.document == "/w/docs/PLAN.md")
    }

    @Test func closingTheViewerClearsItAndTheNextFileOpensANewOne() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        store.closePane(viewer)
        #expect(store.workspace(id)?.viewer == nil)
        let openedNext = store.showDocument("/w/plan.md", from: shell)

        let next = try #require(openedNext)
        #expect(next != viewer)
        #expect(store.workspace(id)?.viewer == next)
    }

    @Test func showingAFileEndsAZoomThatHidesIt() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        store.toggleZoom(shell)
        store.showDocument("/w/notes.md", from: shell)
        #expect(store.workspace(id)?.tree.zoomed == nil)

        store.toggleZoom(viewer)
        store.showDocument("/w/other.md", from: viewer)
        #expect(store.workspace(id)?.tree.zoomed == viewer)
    }

    @Test func splittingADocumentStartsAShellInTheWorkspaceFolder() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        let openedAdded = store.split(viewer, toward: .down)

        let added = try #require(openedAdded)
        let pane = try #require(store.workspace(id)?.tree.pane(added))
        #expect(pane.document == nil)
        #expect(pane.workingDirectory == "/w")
    }

    /// The viewer keeps its full height column.
    @Test func aLauncherOpensBesideTheTerminalsNotTheViewer() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        let column = frame(of: viewer, in: store)
        store.openPane(running: "claude", in: id, bounds: bounds)
        #expect(frame(of: viewer, in: store) == column)
    }

    @Test func archivingTheWorkspaceClearsItsViewer() throws {
        var (store, id, shell) = try makeStore()
        store.showDocument("/w/plan.md", from: shell)
        store.open(folder: "/other")
        store.setArchived(id, true)
        #expect(store.workspace(id)?.viewer == nil)
    }

    // MARK: Opening from Finder

    @Test func aFileFromFinderGetsAWorkspaceOfItsOwn() throws {
        var (store, _, _) = try makeStore()
        let pane = store.openDocument("/Users/me/Downloads/report.pdf")
        let workspace = try #require(store.selectedWorkspace)
        #expect(workspace.folder == "/Users/me/Downloads")
        #expect(workspace.name == "report.pdf")
        #expect(workspace.tree.panes.map(\.id) == [pane])
        #expect(workspace.tree.pane(pane)?.document == "/Users/me/Downloads/report.pdf")
        #expect(workspace.viewer == pane)
        #expect(workspace.focusedPane == pane)
        #expect(store.workspaces.count == 2)
    }

    @Test func aFileAlreadyShownIsSelectedNotOpenedAgain() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)

        let viewer = try #require(openedViewer)
        store.open(folder: "/other")
        let shown = store.openDocument("/w/plan.md")

        #expect(shown == viewer)
        #expect(store.selection == id)
        #expect(store.workspace(id)?.focusedPane == viewer)
        #expect(store.workspaces.count == 2)
    }

    @Test func twoFilesWithOneNameGetNumberedWorkspaces() throws {
        var store = WorkspaceStore()
        store.openDocument("/a/plan.md")
        store.openDocument("/b/plan.md")
        #expect(store.workspaces.map(\.name) == ["plan.md", "plan.md 2"])
    }

    /// The document stays a full height column on the right.
    @Test func anAgentOpensBesideTheDocumentOnItsLeft() throws {
        var store = WorkspaceStore()
        let document = store.openDocument("/w/plan.md")
        let id = try #require(store.selection)
        let opened = store.openPane(running: "claude", in: id, bounds: bounds)
        let agent = try #require(opened)
        #expect(store.workspace(id)?.tree.panes.map(\.id) == [agent, document])
        let column = try #require(frame(of: document, in: store))
        #expect(column.height == bounds.height)
        #expect(abs(column.minX - bounds.width / 2) <= 1)
        #expect(store.workspace(id)?.focusedPane == agent)
    }

    @Test func closingAPinnedFilesWorkspaceRemovesIt() throws {
        var store = WorkspaceStore()
        let other = store.open(folder: "/other")
        store.openDocument("/w/plan.md")
        let id = try #require(store.selection)
        store.setPinned(id, true)
        store.close(id)
        #expect(store.workspace(id) == nil)
        #expect(store.selection == other)
    }

    // MARK: Moving to another workspace

    @Test func aFileFromFinderMovesBesideATerminalAndItsWorkspaceCloses() throws {
        var (store, id, shell) = try makeStore()
        let document = store.openDocument("/Users/me/Downloads/report.pdf")
        let finder = try #require(store.selection)
        #expect(store.canMovePane(document, toWorkspace: id))
        store.movePane(document, toWorkspace: id)

        #expect(store.workspace(finder) == nil)
        #expect(store.selection == id)
        let workspace = try #require(store.workspace(id))
        #expect(workspace.tree.panes.map(\.id) == [shell, document])
        #expect(workspace.tree.pane(document)?.document == "/Users/me/Downloads/report.pdf")
        #expect(workspace.viewer == document)
        #expect(workspace.focusedPane == document)
        let column = try #require(frame(of: document, in: store))
        #expect(column.height == bounds.height)
        #expect(abs(column.width - bounds.width / 2) <= 1)
    }

    @Test func besideSeveralPanesTheMovedDocumentTakesFortyPercent() throws {
        var (store, id, _) = try makeStore()
        store.openPane(running: "claude", in: id, bounds: bounds)
        let document = store.openDocument("/Users/me/report.pdf")
        store.movePane(document, toWorkspace: id)

        let column = try #require(frame(of: document, in: store))
        #expect(column.height == bounds.height)
        #expect(abs(column.width - bounds.width * 0.4) <= 1)
    }

    /// A Cmd+click still goes to the viewer the workspace had.
    @Test func aWorkspaceWithAViewerKeepsIt() throws {
        var (store, id, shell) = try makeStore()
        let viewer = store.showDocument("/w/plan.md", from: shell)
        let document = store.openDocument("/Users/me/report.pdf")
        store.movePane(document, toWorkspace: id)

        let workspace = try #require(store.workspace(id))
        #expect(workspace.viewer == viewer)
        #expect(workspace.tree.panes.last?.id == document)
        #expect(workspace.focusedPane == document)
    }

    @Test func theWorkspaceItLeavesKeepsItsOtherPanes() throws {
        var (store, id, shell) = try makeStore()
        let openedViewer = store.showDocument("/w/plan.md", from: shell)
        let viewer = try #require(openedViewer)
        store.focus(viewer)
        let other = store.open(folder: "/other")
        store.movePane(viewer, toWorkspace: other)

        let workspace = try #require(store.workspace(id))
        #expect(workspace.tree.panes.map(\.id) == [shell])
        #expect(workspace.focusedPane == shell)
        #expect(workspace.viewer == nil)
        #expect(store.workspace(other)?.tree.contains(viewer) == true)
    }

    /// A terminal's processes were started with its workspace's ID.
    @Test func aTerminalDoesNotMoveToAnotherWorkspace() throws {
        var (store, _, shell) = try makeStore()
        let other = store.open(folder: "/other")
        let before = store
        #expect(!store.canMovePane(shell, toWorkspace: other))
        store.movePane(shell, toWorkspace: other)
        #expect(store == before)
    }

    @Test func aDocumentDoesNotMoveToItsOwnAnArchivedOrAnUnknownWorkspace() throws {
        var (store, id, _) = try makeStore()
        let archived = store.open(folder: "/archived")
        store.setArchived(archived, true)
        let document = store.openDocument("/Users/me/report.pdf")
        let own = try #require(store.selection)
        let before = store
        for target in [own, archived, Workspace.ID()] {
            #expect(!store.canMovePane(document, toWorkspace: target))
            store.movePane(document, toWorkspace: target)
        }
        #expect(!store.canMovePane(Pane.ID(), toWorkspace: id))
        store.movePane(Pane.ID(), toWorkspace: id)
        #expect(store == before)
    }

    // MARK: Launching

    @Test func launchKeepsADocumentWhoseFileIsGone() throws {
        var store = WorkspaceStore()
        let pane = store.openDocument("/gone/plan.md")
        let saved = store
        store.prepareForLaunch(home: "/home") { _ in false }
        #expect(store == saved)
        #expect(store.selectedWorkspace?.tree.pane(pane)?.document == "/gone/plan.md")
    }

    // MARK: Saving

    @Test func documentPanesAndViewersRoundTrip() throws {
        var (store, _, shell) = try makeStore()
        store.showDocument("/w/plan.md", from: shell)
        let data = try JSONEncoder().encode(store)
        #expect(try JSONDecoder().decode(WorkspaceStore.self, from: data) == store)
    }

    /// Beam 0.1 wrote panes without `document` and workspaces without
    /// `viewer`.
    @Test func aTerminalSavesWithoutADocumentKey() throws {
        let (store, _, _) = try makeStore()
        let json = String(decoding: try JSONEncoder().encode(store), as: UTF8.self)
        #expect(!json.contains("document"))
        #expect(!json.contains("viewer"))
    }
}
