import BeamCore
import Foundation
import Testing

struct WorkspaceStoreTests {
    /// Three open workspaces, `/one` selected.
    func makeStore() -> (store: WorkspaceStore, one: Workspace.ID, two: Workspace.ID, three: Workspace.ID) {
        var store = WorkspaceStore()
        let three = store.open(folder: "/three")
        let two = store.open(folder: "/two")
        let one = store.open(folder: "/one")
        return (store, one, two, three)
    }

    func folders(_ workspaces: [Workspace]) -> [String] { workspaces.map(\.folder) }

    // MARK: Opening

    @Test func openingAFolderStartsOneShellThereAndSelectsIt() throws {
        var store = WorkspaceStore()
        let id = store.open(folder: "/Users/me/Code/beam")
        let workspace = try #require(store.workspace(id))
        #expect(store.selection == id)
        #expect(workspace.name == "beam")
        #expect(workspace.tree.panes.map(\.workingDirectory) == ["/Users/me/Code/beam"])
        #expect(workspace.focusedPane == workspace.tree.panes.first?.id)
    }

    @Test func openingAFolderTwiceSelectsTheExistingWorkspace() {
        var (store, one, two, _) = makeStore()
        #expect(store.open(folder: "/two") == two)
        #expect(store.selection == two)
        #expect(store.workspaces.count == 3)
        #expect(store.open(folder: "/one/") == one)
    }

    @Test func creatingAWorkspaceInAnOpenFolderAddsAnother() throws {
        var (store, one, _, _) = makeStore()
        let another = store.create(folder: "/one/")
        #expect(another != one)
        #expect(store.selection == another)
        #expect(folders(store.workspaces) == ["/three", "/two", "/one", "/one"])
        let workspace = try #require(store.workspace(another))
        #expect(workspace.tree.panes.map(\.workingDirectory) == ["/one"])
        #expect(store.open(folder: "/one") == one)
    }

    @Test func aNewWorkspaceIsNumberedUntilItsNameIsFree() {
        var store = WorkspaceStore()
        store.open(folder: "/Users/me/Code/beam")
        let second = store.create(folder: "/Users/me/Code/beam")
        let fork = store.create(folder: "/Users/me/Forks/beam")
        #expect(store.workspace(second)?.name == "beam 2")
        #expect(store.workspace(fork)?.name == "beam 3")
        store.rename(second, to: "review")
        let third = store.create(folder: "/Users/me/Code/beam")
        #expect(store.workspace(third)?.name == "beam 2")
    }

    @Test func renamingTrimsTheNameAndAnEmptyNameIsTheFolders() {
        var (store, one, _, _) = makeStore()
        store.rename(one, to: "  api server\n")
        #expect(store.workspace(one)?.name == "api server")
        store.rename(one, to: " \t")
        #expect(store.workspace(one)?.name == "one")
    }

    @Test func openingAnArchivedFolderBringsItBack() {
        var (store, _, two, _) = makeStore()
        store.setArchived(two, true)
        #expect(store.open(folder: "/two") == two)
        #expect(store.workspace(two)?.isArchived == false)
        #expect(store.workspace(two)?.tree.isEmpty == false)
    }

    // MARK: Order and switching

    @Test func sidebarListsPinnedFirstAndHidesArchived() {
        var (store, _, two, three) = makeStore()
        #expect(folders(store.sidebar) == ["/three", "/two", "/one"])
        store.setPinned(two, true)
        #expect(folders(store.sidebar) == ["/two", "/three", "/one"])
        store.setArchived(three, true)
        #expect(folders(store.sidebar) == ["/two", "/one"])
        store.showsArchived = true
        #expect(folders(store.sidebar) == ["/two", "/one", "/three"])
    }

    @Test func selectingByPositionFollowsTheSidebar() {
        var (store, one, two, three) = makeStore()
        store.select(at: 0)
        #expect(store.selection == three)
        store.select(at: 2)
        #expect(store.selection == one)
        store.select(at: 9)
        #expect(store.selection == one)
        store.setPinned(two, true)
        store.select(at: 0)
        #expect(store.selection == two)
    }

    @Test func nextAndPreviousWrapAroundTheSidebar() {
        var (store, one, _, three) = makeStore()
        store.selectNext()
        #expect(store.selection == three)
        store.selectPrevious()
        #expect(store.selection == one)
    }

    @Test func switchingSkipsShownArchivedWorkspaces() {
        var (store, one, two, three) = makeStore()
        store.setArchived(two, true)
        store.showsArchived = true
        #expect(folders(store.unarchived) == ["/three", "/one"])

        store.select(at: 2)
        #expect(store.selection == one)
        store.selectNext()
        #expect(store.selection == three)
        store.selectPrevious()
        #expect(store.selection == one)
        #expect(store.workspace(two)?.isArchived == true)
    }

    // MARK: Reordering

    @Test func movingAWorkspaceReordersItsSection() {
        var (store, one, _, three) = makeStore()
        store.moveWorkspace(one, pinned: false, to: 0)
        #expect(folders(store.sidebar) == ["/one", "/three", "/two"])
        store.moveWorkspace(one, pinned: false, to: 3)
        #expect(folders(store.sidebar) == ["/three", "/two", "/one"])
        store.moveWorkspace(three, pinned: false, to: 2)
        #expect(folders(store.sidebar) == ["/two", "/three", "/one"])
    }

    @Test func droppingAWorkspaceWhereItIsChangesNothing() {
        var (store, _, two, three) = makeStore()
        store.setPinned(three, true)
        let before = store
        store.moveWorkspace(three, pinned: true, to: 0)
        store.moveWorkspace(three, pinned: true, to: 1)
        store.moveWorkspace(two, pinned: false, to: 0)
        store.moveWorkspace(two, pinned: false, to: 1)
        #expect(store == before)
    }

    @Test func aWorkspaceDroppedInTheOtherSectionJoinsIt() {
        var (store, one, two, three) = makeStore()
        store.setPinned(three, true)

        // The end of the pinned section and the start of the rest are the
        // same place in the list; the section says which was meant.
        store.moveWorkspace(two, pinned: true, to: 1)
        #expect(folders(store.sidebar) == ["/three", "/two", "/one"])
        #expect(store.workspace(two)?.isPinned == true)

        store.moveWorkspace(three, pinned: false, to: 0)
        #expect(folders(store.sidebar) == ["/two", "/three", "/one"])
        #expect(store.workspace(three)?.isPinned == false)

        store.moveWorkspace(one, pinned: true, to: 0)
        #expect(folders(store.sidebar) == ["/one", "/two", "/three"])
        #expect(store.workspace(one)?.isPinned == true)
    }

    @Test func archivedWorkspacesStayLastAndDoNotMove() {
        var (store, one, two, _) = makeStore()
        store.setArchived(two, true)
        store.showsArchived = true
        store.moveWorkspace(two, pinned: false, to: 0)
        #expect(folders(store.sidebar) == ["/three", "/one", "/two"])
        store.moveWorkspace(one, pinned: false, to: 0)
        #expect(folders(store.sidebar) == ["/one", "/three", "/two"])
    }

    @Test func switchingByNumberFollowsTheNewOrder() {
        var (store, one, _, _) = makeStore()
        store.select(at: 0)
        store.moveWorkspace(one, pinned: false, to: 0)
        store.select(at: 0)
        #expect(store.selection == one)
    }

    // MARK: Panes

    @Test func movingAPaneRearrangesItsWorkspaceAndFocusesIt() throws {
        var (store, one, _, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        let secondResult = store.split(first, toward: .right)
        let second = try #require(secondResult)
        store.focus(first)

        store.movePane(second, onto: first, .beside(.up))
        let workspace = try #require(store.workspace(one))
        #expect(workspace.tree.panes.map(\.id) == [second, first])
        #expect(workspace.focusedPane == second)
    }

    @Test func aPaneDoesNotMoveIntoAnotherWorkspace() throws {
        var (store, one, two, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        let other = try #require(store.workspace(two)?.focusedPane)
        let before = store
        store.movePane(first, onto: other, .beside(.left))
        store.movePane(first, onto: first, .swap)
        #expect(store == before)
    }

    @Test func splitAddsAFocusedPaneInTheWorkspaceFolder() throws {
        var (store, one, _, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        store.updatePane(first) { $0.workingDirectory = "/one/src" }
        let addedResult = store.split(first, toward: .right)
        let added = try #require(addedResult)
        let workspace = try #require(store.workspace(one))
        #expect(workspace.tree.panes.map(\.id) == [first, added])
        #expect(workspace.tree.pane(added)?.workingDirectory == "/one")
        #expect(workspace.focusedPane == added)
    }

    @Test func focusingAnotherPaneEndsZoom() throws {
        var (store, one, _, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        let secondResult = store.split(first, toward: .down)
        let second = try #require(secondResult)
        store.toggleZoom(second)
        #expect(store.workspace(one)?.tree.zoomed == second)
        store.focus(second)
        #expect(store.workspace(one)?.tree.zoomed == second)
        store.focus(first)
        #expect(store.workspace(one)?.tree.zoomed == nil)
        #expect(store.workspace(one)?.focusedPane == first)
    }

    @Test func treeChangesFindTheWorkspaceByID() throws {
        var (store, one, two, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        store.split(first, toward: .right)
        var expected = try #require(store.workspace(one)?.tree)
        expected.setRatio(0.3, at: [])
        let untouched = store.workspace(two)

        store.modifyTree(of: one) { $0.setRatio(0.3, at: []) }
        #expect(store.workspace(one)?.tree == expected)
        #expect(store.workspace(two) == untouched)
    }

    @Test func closingAPaneFocusesItsNeighbour() throws {
        var (store, one, _, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        let secondResult = store.split(first, toward: .right)
        let second = try #require(secondResult)
        store.closePane(second)
        #expect(store.workspace(one)?.focusedPane == first)
        #expect(store.workspace(one)?.tree.panes.map(\.id) == [first])
    }

    @Test func closingTheLastPaneClosesTheWorkspaceAndSelectsTheNextOne() throws {
        var (store, one, two, three) = makeStore()
        store.select(two)
        store.closePane(try #require(store.workspace(two)?.focusedPane))
        #expect(store.workspace(two) == nil)
        #expect(store.selection == one)

        store.closePane(try #require(store.workspace(one)?.focusedPane))
        #expect(store.selection == three)

        store.closePane(try #require(store.workspace(three)?.focusedPane))
        #expect(store.workspaces.isEmpty)
        #expect(store.selection == nil)
    }

    @Test func aPinnedWorkspaceOutlivesItsLastPane() throws {
        var (store, one, two, _) = makeStore()
        store.setPinned(two, true)
        store.select(two)
        store.closePane(try #require(store.workspace(two)?.focusedPane))
        #expect(store.workspace(two)?.tree.isEmpty == true)
        #expect(store.workspace(two)?.focusedPane == nil)
        #expect(store.selection != two)
        _ = one
    }

    @Test func selectionSkipsEmptyWorkspacesAndEndsWhenNoneAreOpen() throws {
        var store = WorkspaceStore()
        let pinned = store.open(folder: "/pinned")
        store.setPinned(pinned, true)
        store.closePane(try #require(store.workspace(pinned)?.focusedPane))
        #expect(store.selection == nil)
    }

    @Test func selectingAnEmptyWorkspaceStartsAShellInItsFolder() throws {
        var (store, _, two, _) = makeStore()
        store.setPinned(two, true)
        store.close(two)
        store.select(two)
        let workspace = try #require(store.workspace(two))
        #expect(workspace.tree.panes.map(\.workingDirectory) == ["/two"])
        #expect(workspace.focusedPane == workspace.tree.panes.first?.id)
    }

    @Test func openingAPaneTilesItInTheWorkspaceFolderAndFocusesIt() throws {
        var (store, one, _, _) = makeStore()
        let first = try #require(store.workspace(one)?.focusedPane)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let opened = store.openPane(running: "claude", in: one, bounds: bounds)
        let added = try #require(opened)
        let workspace = try #require(store.workspace(one))
        #expect(workspace.tree.panes.map(\.id) == [first, added])
        #expect(workspace.tree.pane(added)?.workingDirectory == "/one")
        #expect(workspace.tree.pane(added)?.command == "claude")
        #expect(workspace.focusedPane == added)
    }

    @Test func aPaneCanOpenInAnotherFolder() throws {
        var (store, one, _, _) = makeStore()
        let opened = store.openPane(running: "brew upgrade gemini-cli", in: one, folder: "/home", bounds: .zero)
        let added = try #require(opened)
        #expect(store.workspace(one)?.tree.pane(added)?.workingDirectory == "/home")
        #expect(store.workspace(one)?.folder == "/one")
    }

    @Test func openingAPaneInAnEmptyWorkspaceFillsIt() throws {
        var (store, one, two, _) = makeStore()
        store.setPinned(two, true)
        store.close(two)
        let opened = store.openPane(running: nil, in: two, bounds: .zero)
        let added = try #require(opened)
        #expect(store.workspace(two)?.tree.panes.map(\.id) == [added])
        #expect(store.workspace(two)?.focusedPane == added)
        #expect(store.selection == one)
        let unknown = store.openPane(running: nil, in: Workspace.ID(), bounds: .zero)
        #expect(unknown == nil)
    }

    // MARK: Pin, archive, colour

    @Test func archivingClosesThePanesAndSelectsTheAdjacentWorkspace() {
        var (store, one, two, _) = makeStore()
        store.setArchived(one, true)
        #expect(store.workspace(one)?.isArchived == true)
        #expect(store.workspace(one)?.tree.isEmpty == true)
        #expect(store.selection == two)
    }

    @Test func colourIsStored() {
        var (store, one, _, _) = makeStore()
        store.setColor(one, .purple)
        #expect(store.workspace(one)?.color == .purple)
        store.setColor(one, nil)
        #expect(store.workspace(one)?.color == nil)
    }

    @Test func paneIDsAreFoundAcrossWorkspaces() throws {
        let (store, _, two, _) = makeStore()
        let pane = try #require(store.workspace(two)?.focusedPane)
        #expect(store.workspaceID(containing: pane) == two)
    }

    // MARK: Launch

    @Test func launchKeepsAnOpenSelection() {
        var (store, _, _, _) = makeStore()
        let saved = store
        store.prepareForLaunch(home: "/home") { _ in true }
        #expect(store == saved)
    }

    @Test func launchReopensTheFirstPinnedWorkspaceWhenNoneWasOpen() throws {
        var store = WorkspaceStore()
        let first = store.open(folder: "/first")
        let second = store.open(folder: "/second")
        store.setPinned(first, true)
        store.setPinned(second, true)
        store.close(second)
        store.close(first)
        #expect(store.selection == nil)

        store.prepareForLaunch(home: "/home") { _ in true }
        #expect(store.selection == first)
        #expect(store.workspace(first)?.tree.panes.map(\.workingDirectory) == ["/first"])
        #expect(store.workspace(second)?.tree.isEmpty == true)
        #expect(folders(store.sidebar) == ["/first", "/second"])
    }

    @Test func launchWithNothingSavedOpensHome() {
        var store = WorkspaceStore()
        store.prepareForLaunch(home: "/Users/me") { _ in true }
        #expect(folders(store.sidebar) == ["/Users/me"])
        #expect(store.selectedWorkspace?.folder == "/Users/me")
    }

    @Test func launchWithEveryWorkspaceArchivedOpensHome() {
        var (store, one, two, three) = makeStore()
        for id in [one, two, three] { store.setArchived(id, true) }
        store.prepareForLaunch(home: "/home") { _ in true }
        #expect(store.selectedWorkspace?.folder == "/home")
        #expect(store.workspace(one)?.isArchived == true)
    }

    @Test func launchMovesPanesOutOfDirectoriesThatAreGone() throws {
        var store = WorkspaceStore()
        let kept = store.open(folder: "/kept")
        let pane = try #require(store.workspace(kept)?.focusedPane)
        store.updatePane(pane) { $0.workingDirectory = "/kept/deleted-worktree" }
        let gone = store.open(folder: "/gone")

        store.prepareForLaunch(home: "/home") { ["/kept", "/home"].contains($0) }
        #expect(store.workspace(kept)?.tree.panes.map(\.workingDirectory) == ["/kept"])
        #expect(store.workspace(gone)?.tree.panes.map(\.workingDirectory) == ["/home"])
        #expect(store.selection == gone)
    }

    @Test func launchResumesAgentsAndRunsOtherCommandsAgain() throws {
        var store = WorkspaceStore()
        let id = store.open(folder: "/w")
        let shell = try #require(store.workspace(id)?.focusedPane)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let openedClaude = store.openPane(running: "claude", in: id, bounds: bounds)
        let openedServer = store.openPane(running: "npm run dev", in: id, bounds: bounds)
        let claude = try #require(openedClaude)
        let server = try #require(openedServer)

        store.prepareForLaunch(home: "/home") { _ in true }
        let tree = try #require(store.workspace(id)?.tree)
        #expect(tree.pane(shell)?.command == nil)
        #expect(tree.pane(claude)?.command == "claude --continue")
        #expect(tree.pane(server)?.command == "npm run dev")
    }

    @Test func launchResumesTheSessionAnAgentReported() throws {
        var store = WorkspaceStore()
        let id = store.open(folder: "/w")
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let openedClaude = store.openPane(running: "claude", in: id, bounds: bounds)
        let openedCodex = store.openPane(running: "codex", in: id, bounds: bounds)
        let claude = try #require(openedClaude)
        let codex = try #require(openedCodex)
        store.updatePane(claude) { $0.agentSession = "00893aaf-19fa-41d2-8238-13269b9b3ca0" }
        store.updatePane(codex) { $0.agentSession = "11111111-2222-7333-8444-555555555555" }

        store.prepareForLaunch(home: "/home") { _ in true }
        let tree = try #require(store.workspace(id)?.tree)
        #expect(tree.pane(claude)?.command == "claude --resume 00893aaf-19fa-41d2-8238-13269b9b3ca0")
        #expect(tree.pane(codex)?.command == "codex resume 11111111-2222-7333-8444-555555555555")
        #expect(tree.pane(claude)?.agentSession == "00893aaf-19fa-41d2-8238-13269b9b3ca0")
    }

    @Test func aPaneWithoutAnAgentSessionLoads() throws {
        let pane = try JSONDecoder().decode(
            Pane.self,
            from: Data(
                #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","workingDirectory":"/w","command":"claude"}"#.utf8))
        #expect(pane.command == "claude")
        #expect(pane.agentSession == nil)
    }

    // MARK: Persistence

    @Test func storeRoundTripsThroughJSON() throws {
        var (store, one, two, _) = makeStore()
        store.setPinned(two, true)
        store.setColor(one, .green)
        store.showsArchived = true
        let data = try JSONEncoder().encode(store)
        #expect(try JSONDecoder().decode(WorkspaceStore.self, from: data) == store)
    }
}
