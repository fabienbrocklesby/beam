import CoreGraphics

// Geometry for drawing a tree, dragging its dividers, moving between panes and
// placing new ones.
// Coordinates have y growing downward, as in a flipped NSView.
extension SplitTree {
    public struct Layout: Equatable, Sendable {
        public var frames: [Pane.ID: CGRect] = [:]
        /// In tree order, outermost split first.
        public var dividers: [Divider] = []
    }

    /// The line between a split's two children.
    public struct Divider: Equatable, Sendable {
        public let path: Path
        public let axis: Axis
        public let frame: CGRect
        /// The whole split, which a drag position is measured against.
        public let splitFrame: CGRect
        /// How many panes sit side by side along `axis` on each side, which
        /// each need room when the divider moves.
        let firstWeight: Int
        let secondWeight: Int

        private static let snapFractions = [1.0 / 3.0, 0.5, 2.0 / 3.0]

        /// The split ratio that puts this divider's centre at `position` on
        /// its axis, keeping every pane along the axis on either side at
        /// least `minimumExtent` long and snapping to halves and thirds
        /// within `snapDistance`. When the split is too small for that, the
        /// sides share what there is by weight.
        public func ratio(forPosition position: Double, minimumExtent: Double, snapDistance: Double) -> Double {
            let thickness = axis.length(of: frame)
            let available = axis.length(of: splitFrame) - thickness
            guard available > 0 else { return 0.5 }
            func minimum(weight: Int) -> Double {
                Double(weight) * minimumExtent + Double(weight - 1) * thickness
            }
            let fit = min(1, available / (minimum(weight: firstWeight) + minimum(weight: secondWeight)))
            let lower = minimum(weight: firstWeight) * fit
            let upper = available - minimum(weight: secondWeight) * fit
            let extent = position - axis.start(of: splitFrame) - thickness / 2

            let snap = Self.snapFractions.first { fraction in
                let target = fraction * available
                return abs(extent - target) <= snapDistance && target >= lower && target <= upper
            }
            if let snap { return snap }
            return min(max(extent, lower), upper) / available
        }
    }

    /// Frames for the visible panes and dividers. A zoomed pane fills
    /// `bounds` alone. Frames are whole points so pane edges stay sharp.
    public func layout(in bounds: CGRect, dividerThickness: Double) -> Layout {
        if let zoomed {
            return Layout(frames: [zoomed: bounds])
        }
        return arrangement(in: bounds, dividerThickness: dividerThickness)
    }

    /// Moves the divider nearest to `id` on `direction`'s axis by `amount`
    /// points. Does nothing when no split on that axis contains `id`.
    public mutating func resize(
        _ id: Pane.ID,
        toward direction: Direction,
        by amount: Double,
        in bounds: CGRect,
        dividerThickness: Double,
        minimumExtent: Double
    ) {
        guard let path = root?.path(to: id) else { return }
        let dividers = arrangement(in: bounds, dividerThickness: dividerThickness).dividers
        for depth in path.indices.reversed() {
            let splitPath = Array(path[..<depth])
            guard let divider = dividers.first(where: { $0.path == splitPath }), divider.axis == direction.axis else {
                continue
            }
            let position = direction.axis.middle(of: divider.frame) + (direction.isForward ? amount : -amount)
            setRatio(divider.ratio(forPosition: position, minimumExtent: minimumExtent, snapDistance: 0), at: splitPath)
            return
        }
    }

    /// Adds `pane` beside the largest pane on screen, splitting that one
    /// across its longer side, so panes opened one after another fill a grid
    /// and the others stay where they are. Panes within 1% of the largest
    /// count as equal and the later in reading order wins, so the first pane,
    /// usually the user's own shell, keeps its space longest.
    public mutating func tile(_ pane: Pane, in bounds: CGRect) {
        let frames = arrangement(in: bounds, dividerThickness: 0).frames
        var largest: (id: Pane.ID, frame: CGRect)?
        for existing in panes {
            guard let frame = frames[existing.id] else { continue }
            if let largest, frame.width * frame.height < largest.frame.width * largest.frame.height * 0.99 { continue }
            largest = (existing.id, frame)
        }
        guard let largest else {
            self = SplitTree(pane)
            return
        }
        split(largest.id, toward: largest.frame.width >= largest.frame.height ? .right : .down, inserting: pane)
    }

    /// The pane next to `id` on screen in `direction`, ignoring zoom. Of the
    /// panes beside it, the nearest wins, then the one level with `id`'s
    /// centre, then the first in reading order.
    public func neighbour(of id: Pane.ID, toward direction: Direction, in bounds: CGRect) -> Pane.ID? {
        let frames = arrangement(in: bounds, dividerThickness: 0).frames
        guard let origin = frames[id] else { return nil }
        let axis = direction.axis
        let cross = axis.perpendicular
        let centre = cross.middle(of: origin)

        let candidates = panes.compactMap { pane -> (id: Pane.ID, gap: Double, offset: Double)? in
            guard pane.id != id, let frame = frames[pane.id] else { return nil }
            let gap =
                direction.isForward
                ? axis.start(of: frame) - axis.end(of: origin)
                : axis.start(of: origin) - axis.end(of: frame)
            let overlap =
                min(cross.end(of: frame), cross.end(of: origin)) - max(cross.start(of: frame), cross.start(of: origin))
            guard gap > -0.5, overlap > 0.5 else { return nil }
            let offset = max(cross.start(of: frame) - centre, centre - cross.end(of: frame), 0)
            return (pane.id, gap, offset)
        }
        return candidates.min { ($0.gap, $0.offset) < ($1.gap, $1.offset) }?.id
    }

    private func arrangement(in bounds: CGRect, dividerThickness: Double) -> Layout {
        var layout = Layout()
        root?.arrange(in: bounds, thickness: dividerThickness, path: [], into: &layout)
        return layout
    }
}

extension SplitTree.Node {
    fileprivate func arrange(
        in rect: CGRect, thickness: Double, path: SplitTree.Path, into layout: inout SplitTree.Layout
    ) {
        switch self {
        case .pane(let pane):
            layout.frames[pane.id] = rect
        case .split(let split):
            let (first, divider, second) = split.axis.divide(rect, ratio: split.ratio, thickness: thickness)
            layout.dividers.append(
                SplitTree.Divider(
                    path: path, axis: split.axis, frame: divider, splitFrame: rect,
                    firstWeight: split.first.weight(along: split.axis),
                    secondWeight: split.second.weight(along: split.axis)))
            split.first.arrange(in: first, thickness: thickness, path: path + [.first], into: &layout)
            split.second.arrange(in: second, thickness: thickness, path: path + [.second], into: &layout)
        }
    }
}

extension SplitTree.Axis {
    var perpendicular: Self { self == .horizontal ? .vertical : .horizontal }

    func start(of rect: CGRect) -> Double { self == .horizontal ? rect.minX : rect.minY }
    func end(of rect: CGRect) -> Double { self == .horizontal ? rect.maxX : rect.maxY }
    func middle(of rect: CGRect) -> Double { self == .horizontal ? rect.midX : rect.midY }
    func length(of rect: CGRect) -> Double { self == .horizontal ? rect.width : rect.height }

    /// Cuts `rect` into the first child, the divider and the second child.
    func divide(_ rect: CGRect, ratio: Double, thickness: Double) -> (CGRect, CGRect, CGRect) {
        let available = max(length(of: rect) - thickness, 0)
        let first = (available * ratio).rounded()
        let second = available - first
        switch self {
        case .horizontal:
            return (
                CGRect(x: rect.minX, y: rect.minY, width: first, height: rect.height),
                CGRect(x: rect.minX + first, y: rect.minY, width: thickness, height: rect.height),
                CGRect(x: rect.minX + first + thickness, y: rect.minY, width: second, height: rect.height)
            )
        case .vertical:
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: first),
                CGRect(x: rect.minX, y: rect.minY + first, width: rect.width, height: thickness),
                CGRect(x: rect.minX, y: rect.minY + first + thickness, width: rect.width, height: second)
            )
        }
    }
}
