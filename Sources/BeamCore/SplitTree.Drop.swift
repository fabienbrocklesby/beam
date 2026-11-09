import CoreGraphics

extension SplitTree {
    /// Where a pane dragged onto another lands. Coordinates have y growing
    /// downward, as in a flipped NSView.
    public enum Drop: Equatable, Sendable {
        /// The two panes trade places.
        case swap
        /// The target splits in two, with the dragged pane on this side.
        case beside(Direction)

        /// How far into a pane, as a share of its width or height, the
        /// pointer has to be before a drop swaps rather than splits.
        private static let swapInset = 0.3

        /// What dropping at `point` on a pane filling `frame` does: the middle
        /// swaps, anywhere else splits toward the nearest edge. Distances are
        /// shares of the pane's size, so a wide pane's edges are as easy to
        /// reach as a tall one's.
        public init(at point: CGPoint, in frame: CGRect) {
            let x = frame.width > 0 ? (point.x - frame.minX) / frame.width : 0.5
            let y = frame.height > 0 ? (point.y - frame.minY) / frame.height : 0.5
            let edges: [(Direction, Double)] = [(.left, x), (.right, 1 - x), (.up, y), (.down, 1 - y)]
            let nearest = edges.min { $0.1 < $1.1 } ?? (.right, 0)
            self = nearest.1 >= Self.swapInset ? .swap : .beside(nearest.0)
        }

        /// The part of `frame` the dragged pane would take.
        public func preview(in frame: CGRect) -> CGRect {
            switch self {
            case .swap:
                return frame
            case .beside(let direction):
                let (first, _, second) = direction.axis.divide(frame, ratio: 0.5, thickness: 0)
                return direction.isForward ? second : first
            }
        }
    }
}
