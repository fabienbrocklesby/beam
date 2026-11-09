/// The panes of one workspace, as a binary tree of splits.
public struct SplitTree: Codable, Equatable, Sendable {
    /// How a split lays out its two children.
    public enum Axis: String, Codable, Sendable {
        /// Side by side, first on the left.
        case horizontal
        /// Stacked, first on top.
        case vertical
    }

    public enum Direction: String, Codable, Sendable, CaseIterable {
        case left, right, up, down

        public var axis: Axis { self == .left || self == .right ? .horizontal : .vertical }

        /// Right and down point from a split's first child to its second.
        var isForward: Bool { self == .right || self == .down }
    }

    public indirect enum Node: Equatable, Sendable {
        case pane(Pane)
        case split(Split)
    }

    public struct Split: Codable, Equatable, Sendable {
        public var axis: Axis
        /// The share of the split's length that goes to `first`, from 0 to 1.
        public var ratio: Double
        public var first: Node
        public var second: Node
    }

    /// One step from a split to a child.
    public enum Branch: String, Codable, Sendable {
        case first, second
    }

    /// The steps from the root to a split.
    public typealias Path = [Branch]

    public private(set) var root: Node?
    /// The pane shown alone, filling the workspace, if any.
    public private(set) var zoomed: Pane.ID?

    public init() {}

    public init(_ pane: Pane) {
        root = .pane(pane)
    }

    public var isEmpty: Bool { root == nil }

    /// Every pane in reading order: left to right, then top to bottom.
    public var panes: [Pane] {
        var panes: [Pane] = []
        root?.collect(into: &panes)
        return panes
    }

    public func contains(_ id: Pane.ID) -> Bool { root?.path(to: id) != nil }

    public func pane(_ id: Pane.ID) -> Pane? { panes.first { $0.id == id } }

    public func pane(after id: Pane.ID) -> Pane.ID? { pane(offsetBy: 1, from: id) }

    public func pane(before id: Pane.ID) -> Pane.ID? { pane(offsetBy: -1, from: id) }

    private func pane(offsetBy offset: Int, from id: Pane.ID) -> Pane.ID? {
        let ids = panes.map(\.id)
        guard ids.count > 1, let index = ids.firstIndex(of: id) else { return nil }
        return ids[(index + offset + ids.count) % ids.count]
    }

    // MARK: Changing panes

    public mutating func updatePane(_ id: Pane.ID, _ update: (inout Pane) -> Void) {
        root = root?.replacingPane(id) { pane in
            var pane = pane
            update(&pane)
            return .pane(pane)
        }
    }

    /// Splits `id` in two, with `pane` on the `direction` side, sharing the
    /// space equally.
    public mutating func split(_ id: Pane.ID, toward direction: Direction, inserting pane: Pane) {
        guard let root, contains(id) else { return }
        self.root = root.replacingPane(id) { existing in
            let (first, second) = direction.isForward ? (existing, pane) : (pane, existing)
            return .split(Split(axis: direction.axis, ratio: 0.5, first: .pane(first), second: .pane(second)))
        }
        zoomed = nil
    }

    /// Removes `id` and gives its space to its sibling.
    ///
    /// - Returns: The pane that should take focus: the one in the sibling
    ///   nearest to where `id` was, or nil when the tree is now empty.
    @discardableResult
    public mutating func remove(_ id: Pane.ID) -> Pane.ID? {
        guard let root, contains(id) else { return nil }
        var focus: Pane.ID?
        self.root = root.removing(id, focus: &focus)
        zoomed = nil
        return focus
    }

    /// Moves `id` onto `target` as `drop` says, keeping the moved pane as it
    /// is. Nothing changes when either is missing or they are the same pane.
    public mutating func move(_ id: Pane.ID, onto target: Pane.ID, _ drop: Drop) {
        guard id != target, let moved = pane(id), let replaced = pane(target) else { return }
        switch drop {
        case .swap:
            root = root?.mappingPanes { $0.id == id ? replaced : $0.id == target ? moved : $0 }
            zoomed = nil
        case .beside(let direction):
            remove(id)
            split(target, toward: direction, inserting: moved)
        }
    }

    // MARK: Ratios

    public mutating func setRatio(_ ratio: Double, at path: Path) {
        guard ratio.isFinite else { return }
        root = root?.updatingSplit(at: path[...]) { $0.ratio = min(max(ratio, 0), 1) }
    }

    /// Gives every column and every row the same share of the space.
    public mutating func equalize() {
        root = root?.equalized()
    }

    /// Equalizes one split, leaving the splits inside it alone.
    public mutating func equalize(at path: Path) {
        root = root?.updatingSplit(at: path[...]) { $0.ratio = $0.equalRatio }
    }

    // MARK: Zoom

    /// Shows `id` alone, or shows every pane again if it already is. A tree
    /// with one pane has nothing to zoom.
    public mutating func toggleZoom(_ id: Pane.ID) {
        guard panes.count > 1, contains(id) else { return }
        zoomed = zoomed == id ? nil : id
    }

    public mutating func unzoom() {
        zoomed = nil
    }
}

// MARK: - Node

extension SplitTree.Node: Codable {
    private enum CodingKeys: String, CodingKey {
        case pane, split
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let pane = try container.decodeIfPresent(Pane.self, forKey: .pane) {
            self = .pane(pane)
        } else {
            self = .split(try container.decode(SplitTree.Split.self, forKey: .split))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let pane): try container.encode(pane, forKey: .pane)
        case .split(let split): try container.encode(split, forKey: .split)
        }
    }
}

extension SplitTree.Node {
    func collect(into panes: inout [Pane]) {
        switch self {
        case .pane(let pane):
            panes.append(pane)
        case .split(let split):
            split.first.collect(into: &panes)
            split.second.collect(into: &panes)
        }
    }

    /// The branches from this node down to `id`, or nil if `id` is not
    /// below this node.
    func path(to id: Pane.ID) -> SplitTree.Path? {
        switch self {
        case .pane(let pane):
            return pane.id == id ? [] : nil
        case .split(let split):
            if let path = split.first.path(to: id) { return [.first] + path }
            if let path = split.second.path(to: id) { return [.second] + path }
            return nil
        }
    }

    var leadingPane: Pane {
        switch self {
        case .pane(let pane): pane
        case .split(let split): split.first.leadingPane
        }
    }

    var trailingPane: Pane {
        switch self {
        case .pane(let pane): pane
        case .split(let split): split.second.trailingPane
        }
    }

    func replacingPane(_ id: Pane.ID, with replacement: (Pane) -> Self) -> Self {
        switch self {
        case .pane(let pane):
            return pane.id == id ? replacement(pane) : self
        case .split(var split):
            split.first = split.first.replacingPane(id, with: replacement)
            split.second = split.second.replacingPane(id, with: replacement)
            return .split(split)
        }
    }

    func mappingPanes(_ transform: (Pane) -> Pane) -> Self {
        switch self {
        case .pane(let pane):
            return .pane(transform(pane))
        case .split(var split):
            split.first = split.first.mappingPanes(transform)
            split.second = split.second.mappingPanes(transform)
            return .split(split)
        }
    }

    /// This node without `id`, or nil if this node is `id`.
    func removing(_ id: Pane.ID, focus: inout Pane.ID?) -> Self? {
        switch self {
        case .pane(let pane):
            return pane.id == id ? nil : self
        case .split(var split):
            guard let first = split.first.removing(id, focus: &focus) else {
                focus = split.second.leadingPane.id
                return split.second
            }
            guard let second = split.second.removing(id, focus: &focus) else {
                focus = split.first.trailingPane.id
                return split.first
            }
            split.first = first
            split.second = second
            return .split(split)
        }
    }

    func updatingSplit(at path: ArraySlice<SplitTree.Branch>, _ update: (inout SplitTree.Split) -> Void) -> Self {
        guard case .split(var split) = self else { return self }
        switch path.first {
        case nil: update(&split)
        case .first: split.first = split.first.updatingSplit(at: path.dropFirst(), update)
        case .second: split.second = split.second.updatingSplit(at: path.dropFirst(), update)
        }
        return .split(split)
    }

    func equalized() -> Self {
        guard case .split(var split) = self else { return self }
        split.first = split.first.equalized()
        split.second = split.second.equalized()
        split.ratio = split.equalRatio
        return .split(split)
    }

    /// How many panes sit side by side along `axis`: a split across the axis
    /// is as wide as its widest child.
    func weight(along axis: SplitTree.Axis) -> Int {
        switch self {
        case .pane:
            return 1
        case .split(let split) where split.axis == axis:
            return split.first.weight(along: axis) + split.second.weight(along: axis)
        case .split(let split):
            return max(split.first.weight(along: axis), split.second.weight(along: axis))
        }
    }
}

extension SplitTree.Split {
    /// The ratio that gives every pane along this split's axis the same length.
    var equalRatio: Double {
        let first = Double(first.weight(along: axis))
        return first / (first + Double(second.weight(along: axis)))
    }
}
