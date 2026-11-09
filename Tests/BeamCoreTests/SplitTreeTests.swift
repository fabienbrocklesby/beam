import BeamCore
import CoreGraphics
import Foundation
import Testing

struct SplitTreeTests {
    let a = Pane(workingDirectory: "/a")
    let b = Pane(workingDirectory: "/b")
    let c = Pane(workingDirectory: "/c")
    let d = Pane(workingDirectory: "/d")
    let bounds = CGRect(x: 0, y: 0, width: 1001, height: 601)

    /// a | b, with c below b.
    var threePanes: SplitTree {
        var tree = SplitTree(a)
        tree.split(a.id, toward: .right, inserting: b)
        tree.split(b.id, toward: .down, inserting: c)
        return tree
    }

    // MARK: Structure

    @Test func emptyTreeHasNoPanes() {
        let tree = SplitTree()
        #expect(tree.isEmpty)
        #expect(tree.panes.isEmpty)
    }

    @Test func splittingPlacesTheNewPaneOnTheRequestedSide() {
        var tree = SplitTree(a)
        tree.split(a.id, toward: .right, inserting: b)
        #expect(tree.panes.map(\.id) == [a.id, b.id])

        tree.split(a.id, toward: .left, inserting: c)
        #expect(tree.panes.map(\.id) == [c.id, a.id, b.id])

        tree.split(b.id, toward: .up, inserting: d)
        #expect(tree.panes.map(\.id) == [c.id, a.id, d.id, b.id])
    }

    @Test func splittingAnUnknownPaneChangesNothing() {
        var tree = SplitTree(a)
        tree.split(b.id, toward: .right, inserting: c)
        #expect(tree == SplitTree(a))
    }

    @Test func removingAPaneHandsItsSpaceToItsSibling() {
        var tree = threePanes
        tree.remove(b.id)
        #expect(tree.panes.map(\.id) == [a.id, c.id])
        tree.remove(a.id)
        #expect(tree.panes.map(\.id) == [c.id])
        tree.remove(c.id)
        #expect(tree.isEmpty)
    }

    @Test func removingAPaneFocusesTheNearestPaneInItsSibling() {
        var tree = threePanes
        #expect(tree.remove(a.id) == b.id)

        tree = threePanes
        #expect(tree.remove(c.id) == b.id)

        tree = threePanes
        #expect(tree.remove(b.id) == c.id)

        tree = SplitTree(a)
        #expect(tree.remove(a.id) == nil)
    }

    @Test func updatingAPaneChangesOnlyThatPane() {
        var tree = threePanes
        tree.updatePane(b.id) { $0.workingDirectory = "/elsewhere" }
        #expect(tree.pane(b.id)?.workingDirectory == "/elsewhere")
        #expect(tree.pane(a.id) == a)
    }

    @Test func readingOrderWrapsForNextAndPrevious() {
        let tree = threePanes
        #expect(tree.pane(after: a.id) == b.id)
        #expect(tree.pane(after: c.id) == a.id)
        #expect(tree.pane(before: a.id) == c.id)
        #expect(SplitTree(a).pane(after: a.id) == nil)
    }

    // MARK: Ratios

    @Test func dividerRatioIsClampedToTheUnitInterval() {
        var tree = threePanes
        tree.setRatio(0.25, at: [])
        #expect(tree.layout(in: bounds, dividerThickness: 1).frames[a.id]?.width == 250)
        tree.setRatio(7, at: [])
        #expect(tree.layout(in: bounds, dividerThickness: 1).frames[a.id]?.width == 1000)
    }

    @Test func equalizeGivesEveryColumnAndRowTheSameShare() {
        var tree = SplitTree(a)
        tree.split(a.id, toward: .right, inserting: b)
        tree.split(b.id, toward: .right, inserting: c)
        tree.setRatio(0.9, at: [])
        tree.setRatio(0.1, at: [.second])
        tree.equalize()
        let frames = tree.layout(in: CGRect(x: 0, y: 0, width: 902, height: 600), dividerThickness: 1).frames
        #expect(frames[a.id]?.width == 300)
        #expect(frames[b.id]?.width == 300)
        #expect(frames[c.id]?.width == 300)
    }

    @Test func equalizeCountsAPerpendicularSplitAsOneColumn() {
        var tree = threePanes
        tree.setRatio(0.8, at: [])
        tree.setRatio(0.8, at: [.second])
        tree.equalize()
        let frames = tree.layout(in: bounds, dividerThickness: 1).frames
        #expect(frames[a.id]?.width == 500)
        #expect(frames[b.id]?.height == 300)
    }

    @Test func equalizingOneDividerLeavesTheOthersAlone() {
        var tree = threePanes
        tree.setRatio(0.8, at: [])
        tree.setRatio(0.8, at: [.second])
        tree.equalize(at: [.second])
        let frames = tree.layout(in: bounds, dividerThickness: 1).frames
        #expect(frames[a.id]?.width == 800)
        #expect(frames[b.id]?.height == 300)
    }

    // MARK: Zoom

    @Test func zoomTogglesAndNeedsMoreThanOnePane() {
        var tree = threePanes
        tree.toggleZoom(b.id)
        #expect(tree.zoomed == b.id)
        tree.toggleZoom(b.id)
        #expect(tree.zoomed == nil)

        var single = SplitTree(a)
        single.toggleZoom(a.id)
        #expect(single.zoomed == nil)
    }

    @Test func zoomedPaneFillsTheLayoutAlone() {
        var tree = threePanes
        tree.toggleZoom(c.id)
        let layout = tree.layout(in: bounds, dividerThickness: 1)
        #expect(layout.frames == [c.id: bounds])
        #expect(layout.dividers.isEmpty)
    }

    @Test func splittingOrRemovingEndsZoom() {
        var tree = threePanes
        tree.toggleZoom(c.id)
        tree.split(a.id, toward: .down, inserting: d)
        #expect(tree.zoomed == nil)

        tree.toggleZoom(c.id)
        tree.remove(d.id)
        #expect(tree.zoomed == nil)
    }

    // MARK: Layout

    @Test func layoutTilesTheBoundsWithDividersBetweenPanes() {
        let layout = threePanes.layout(in: bounds, dividerThickness: 1)
        #expect(layout.frames[a.id] == CGRect(x: 0, y: 0, width: 500, height: 601))
        #expect(layout.frames[b.id] == CGRect(x: 501, y: 0, width: 500, height: 300))
        #expect(layout.frames[c.id] == CGRect(x: 501, y: 301, width: 500, height: 300))
        #expect(
            layout.dividers.map(\.frame) == [
                CGRect(x: 500, y: 0, width: 1, height: 601),
                CGRect(x: 501, y: 300, width: 500, height: 1),
            ])
        #expect(layout.dividers.map(\.path) == [[], [.second]])
    }

    @Test func layoutFramesAreWholePoints() {
        var tree = threePanes
        tree.setRatio(1.0 / 3.0, at: [])
        for frame in tree.layout(in: bounds, dividerThickness: 1).frames.values {
            #expect(frame == frame.integral)
        }
    }

    // MARK: Tiling

    /// Each pane's column and row on screen, counting distinct left and top
    /// edges, so a check reads as a grid rather than as point values.
    func cells(_ tree: SplitTree, in bounds: CGRect) -> [Pane.ID: [Int]] {
        let frames = tree.layout(in: bounds, dividerThickness: 1).frames
        let columns = Set(frames.values.map(\.minX)).sorted()
        let rows = Set(frames.values.map(\.minY)).sorted()
        return frames.mapValues { [columns.firstIndex(of: $0.minX) ?? -1, rows.firstIndex(of: $0.minY) ?? -1] }
    }

    @Test func tilingAnEmptyTreeMakesThePaneItsRoot() {
        var tree = SplitTree()
        tree.tile(a, in: bounds)
        #expect(tree == SplitTree(a))
    }

    @Test func tilingFillsAGridOneLargestPaneAtATime() {
        var tree = SplitTree(a)
        tree.tile(b, in: bounds)
        #expect(cells(tree, in: bounds) == [a.id: [0, 0], b.id: [1, 0]])

        // a is a point wider than b after rounding; that still counts as a
        // tie, which goes to the later pane.
        let before = tree.layout(in: bounds, dividerThickness: 1).frames[a.id]
        tree.tile(c, in: bounds)
        #expect(cells(tree, in: bounds) == [a.id: [0, 0], b.id: [1, 0], c.id: [1, 1]])
        #expect(tree.layout(in: bounds, dividerThickness: 1).frames[a.id] == before)

        tree.tile(d, in: bounds)
        #expect(cells(tree, in: bounds) == [a.id: [0, 0], d.id: [0, 1], b.id: [1, 0], c.id: [1, 1]])
    }

    @Test func tilingATallPaneStacksTheNewOneBelow() {
        let tall = CGRect(x: 0, y: 0, width: 600, height: 900)
        var tree = SplitTree(a)
        tree.tile(b, in: tall)
        #expect(cells(tree, in: tall) == [a.id: [0, 0], b.id: [0, 1]])
    }

    @Test func tilingEndsZoom() {
        var tree = threePanes
        tree.toggleZoom(a.id)
        tree.tile(d, in: bounds)
        #expect(tree.zoomed == nil)
        #expect(tree.contains(d.id))
    }

    // MARK: Dragging dividers

    @Test func draggedDividerFollowsThePointer() throws {
        let divider = try #require(threePanes.layout(in: bounds, dividerThickness: 1).dividers.first)
        let ratio = divider.ratio(forPosition: 200.5, minimumExtent: 50, snapDistance: 0)
        #expect(abs(ratio - 0.2) < 0.0001)
    }

    @Test func draggedDividerSnapsToHalvesAndThirds() throws {
        let divider = try #require(threePanes.layout(in: bounds, dividerThickness: 1).dividers.first)
        #expect(divider.ratio(forPosition: 340, minimumExtent: 50, snapDistance: 8) == 1.0 / 3.0)
        #expect(divider.ratio(forPosition: 494, minimumExtent: 50, snapDistance: 8) == 0.5)
        #expect(divider.ratio(forPosition: 660, minimumExtent: 50, snapDistance: 8) == 2.0 / 3.0)
        #expect(divider.ratio(forPosition: 420, minimumExtent: 50, snapDistance: 8) != 0.5)
    }

    @Test func draggedDividerKeepsBothSidesAtTheMinimum() throws {
        let divider = try #require(threePanes.layout(in: bounds, dividerThickness: 1).dividers.first)
        #expect(divider.ratio(forPosition: 3, minimumExtent: 100, snapDistance: 0) == 0.1)
        #expect(divider.ratio(forPosition: 999, minimumExtent: 100, snapDistance: 0) == 0.9)
    }

    @Test func draggedDividerKeepsNestedPanesAtTheMinimum() throws {
        // a | b | c, with b and c in their own split.
        var tree = SplitTree(a)
        tree.split(a.id, toward: .right, inserting: b)
        tree.split(b.id, toward: .right, inserting: c)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let divider = try #require(tree.layout(in: bounds, dividerThickness: 1).dividers.first)

        var dragged = tree
        dragged.setRatio(divider.ratio(forPosition: 990, minimumExtent: 60, snapDistance: 0), at: [])
        var frames = dragged.layout(in: bounds, dividerThickness: 1).frames
        #expect(try #require(frames[b.id]).width >= 60)
        #expect(try #require(frames[c.id]).width >= 60)

        tree.resize(a.id, toward: .right, by: 1000, in: bounds, dividerThickness: 1, minimumExtent: 60)
        frames = tree.layout(in: bounds, dividerThickness: 1).frames
        #expect(try #require(frames[b.id]).width >= 60)
        #expect(try #require(frames[c.id]).width >= 60)
    }

    // MARK: Keyboard resize

    @Test func resizeMovesTheNearestDividerOnThatAxis() {
        var tree = threePanes
        tree.resize(c.id, toward: .up, by: 100, in: bounds, dividerThickness: 1, minimumExtent: 50)
        #expect(tree.layout(in: bounds, dividerThickness: 1).frames[b.id]?.height == 200)

        tree.resize(c.id, toward: .left, by: 100, in: bounds, dividerThickness: 1, minimumExtent: 50)
        #expect(tree.layout(in: bounds, dividerThickness: 1).frames[a.id]?.width == 400)
    }

    @Test func resizeWithNoDividerOnThatAxisChangesNothing() {
        var tree = SplitTree(a)
        tree.split(a.id, toward: .right, inserting: b)
        let before = tree
        tree.resize(a.id, toward: .down, by: 100, in: bounds, dividerThickness: 1, minimumExtent: 50)
        #expect(tree == before)
    }

    // MARK: Spatial focus

    @Test func neighbourFollowsTheScreenLayout() {
        let tree = threePanes
        #expect(tree.neighbour(of: a.id, toward: .right, in: bounds) == b.id)
        #expect(tree.neighbour(of: c.id, toward: .left, in: bounds) == a.id)
        #expect(tree.neighbour(of: b.id, toward: .down, in: bounds) == c.id)
        #expect(tree.neighbour(of: c.id, toward: .up, in: bounds) == b.id)
        #expect(tree.neighbour(of: a.id, toward: .left, in: bounds) == nil)
        #expect(tree.neighbour(of: b.id, toward: .right, in: bounds) == nil)
    }

    @Test func neighbourPrefersThePaneLevelWithTheFocusedOne() {
        // a | b over c, then d below a with a short top: moving right from d
        // should land on c, which sits beside it, not on b.
        var tree = threePanes
        tree.split(a.id, toward: .down, inserting: d)
        tree.setRatio(0.2, at: [.first])
        #expect(tree.neighbour(of: d.id, toward: .right, in: bounds) == c.id)
    }

    @Test func neighbourIgnoresZoom() {
        var tree = threePanes
        tree.toggleZoom(a.id)
        #expect(tree.neighbour(of: a.id, toward: .right, in: bounds) == b.id)
    }

    // MARK: Moving panes

    @Test func aDropSwapsInTheMiddleAndSplitsTowardTheNearestEdge() {
        let frame = CGRect(x: 100, y: 50, width: 400, height: 200)
        #expect(SplitTree.Drop(at: CGPoint(x: 300, y: 150), in: frame) == .swap)
        #expect(SplitTree.Drop(at: CGPoint(x: 110, y: 150), in: frame) == .beside(.left))
        #expect(SplitTree.Drop(at: CGPoint(x: 490, y: 150), in: frame) == .beside(.right))
        #expect(SplitTree.Drop(at: CGPoint(x: 300, y: 55), in: frame) == .beside(.up))
        #expect(SplitTree.Drop(at: CGPoint(x: 300, y: 245), in: frame) == .beside(.down))
        // Edges are measured relative to the pane's size, so a wide pane's
        // corner goes to the edge the pointer is proportionally closer to.
        #expect(SplitTree.Drop(at: CGPoint(x: 105, y: 55), in: frame) == .beside(.left))
        #expect(SplitTree.Drop(at: CGPoint(x: 160, y: 52), in: frame) == .beside(.up))
    }

    @Test func aDropPreviewsTheSpaceThePaneWillTake() {
        let frame = CGRect(x: 100, y: 50, width: 400, height: 200)
        #expect(SplitTree.Drop.swap.preview(in: frame) == frame)
        #expect(SplitTree.Drop.beside(.left).preview(in: frame) == CGRect(x: 100, y: 50, width: 200, height: 200))
        #expect(SplitTree.Drop.beside(.right).preview(in: frame) == CGRect(x: 300, y: 50, width: 200, height: 200))
        #expect(SplitTree.Drop.beside(.up).preview(in: frame) == CGRect(x: 100, y: 50, width: 400, height: 100))
        #expect(SplitTree.Drop.beside(.down).preview(in: frame) == CGRect(x: 100, y: 150, width: 400, height: 100))
    }

    @Test func movingAPaneBesideAnotherSplitsTheTarget() throws {
        var tree = threePanes
        tree.move(a.id, onto: c.id, .beside(.right))
        #expect(tree.panes.map(\.id) == [b.id, c.id, a.id])
        let frames = tree.layout(in: bounds, dividerThickness: 1).frames
        let movedFrame = try #require(frames[a.id])
        let targetFrame = try #require(frames[c.id])
        #expect(movedFrame.minX > targetFrame.minX)
        #expect(movedFrame.minY == targetFrame.minY)
        #expect(tree.pane(a.id) == a)
    }

    @Test func swappingPanesTradesTheirPlaces() {
        let before = threePanes.layout(in: bounds, dividerThickness: 1).frames
        var tree = threePanes
        tree.move(a.id, onto: c.id, .swap)
        #expect(tree.panes.map(\.id) == [c.id, b.id, a.id])
        let after = tree.layout(in: bounds, dividerThickness: 1).frames
        #expect(after[c.id] == before[a.id])
        #expect(after[a.id] == before[c.id])
        #expect(tree.pane(a.id) == a)
    }

    @Test func movingOntoItselfOrAMissingPaneChangesNothing() {
        var tree = threePanes
        tree.move(a.id, onto: a.id, .beside(.down))
        tree.move(a.id, onto: d.id, .swap)
        tree.move(d.id, onto: a.id, .beside(.left))
        #expect(tree == threePanes)
    }

    @Test func movingAPaneEndsZoom() {
        var tree = threePanes
        tree.toggleZoom(b.id)
        tree.move(a.id, onto: c.id, .swap)
        #expect(tree.zoomed == nil)
    }

    // MARK: Persistence

    @Test func treeRoundTripsThroughJSON() throws {
        var tree = threePanes
        tree.setRatio(0.3, at: [])
        tree.toggleZoom(b.id)
        let data = try JSONEncoder().encode(tree)
        #expect(try JSONDecoder().decode(SplitTree.self, from: data) == tree)
    }
}
