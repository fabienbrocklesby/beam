import AppKit
import BeamCore

/// One workspace's panes, laid out flat from its split tree: every pane and
/// every divider is a direct subview, so a resize is a single layout pass and
/// there are no nested split views to keep in step with the tree.
final class WorkspaceView: NSView {
    static let dividerThickness = 1.0
    /// No pane gets shorter or narrower than this from a drag or a resize key.
    static let minimumPaneExtent = 60.0
    /// A dragged divider snaps to a half or a third within this distance.
    private static let snapDistance = 12.0

    /// The user dragged the divider of the split at `path` to `ratio`.
    var onRatioChange: ((SplitTree.Path, Double) -> Void)?
    /// The user double-clicked the divider of the split at `path`.
    var onEqualize: ((SplitTree.Path) -> Void)?

    var style: GhosttyApp.SplitStyle {
        didSet { needsDisplay = true }
    }

    private var tree = SplitTree()
    private var dividers: [DividerView] = []
    private var paneViews: [PaneView] { subviews.compactMap { $0 as? PaneView } }

    init(style: GhosttyApp.SplitStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    // The background shows through the gaps between panes as the dividers.
    override func updateLayer() {
        layer?.backgroundColor = style.dividerColor.cgColor
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // A hidden workspace's terminals stop rendering until it is shown again.
    override func viewDidHide() {
        super.viewDidHide()
        updateVisibility()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateVisibility()
    }

    /// Shows `workspace`'s panes from `views`, which must hold a view for each.
    func show(_ workspace: Workspace, views: [Pane.ID: PaneView]) {
        tree = workspace.tree
        let wanted = tree.panes.compactMap { views[$0.id] }
        for view in paneViews where !wanted.contains(view) {
            view.removeFromSuperview()
        }
        for view in wanted where view.superview !== self {
            // Below the dividers, so their grab areas stay on top.
            addSubview(view, positioned: .below, relativeTo: dividers.first)
        }

        let shown = tree.zoomed.map { [$0] } ?? tree.panes.map(\.id)
        for view in wanted {
            if !shown.contains(view.id) {
                view.emphasis = .unfocused
            } else if shown.count == 1 {
                view.emphasis = .none
            } else {
                view.emphasis = view.id == workspace.focusedPane ? .focused : .unfocused
            }
        }
        updateVisibility()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let layout = tree.layout(in: bounds, dividerThickness: Self.dividerThickness)
        for view in paneViews {
            if let frame = layout.frames[view.id] {
                view.frame = frame
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }

        while dividers.count > layout.dividers.count {
            dividers.removeLast().removeFromSuperview()
        }
        for (index, divider) in layout.dividers.enumerated() {
            if dividers.indices.contains(index) {
                dividers[index].divider = divider
            } else {
                dividers.append(makeDividerView(divider))
            }
        }
    }

    private func updateVisibility() {
        for view in paneViews {
            view.terminal.setVisible(!isHiddenOrHasHiddenAncestor && (tree.zoomed == nil || tree.zoomed == view.id))
        }
    }

    private func makeDividerView(_ divider: SplitTree.Divider) -> DividerView {
        let view = DividerView(divider: divider)
        view.onDrag = { [weak self] divider, position in
            let ratio = divider.ratio(
                forPosition: position, minimumExtent: Self.minimumPaneExtent, snapDistance: Self.snapDistance)
            self?.onRatioChange?(divider.path, ratio)
        }
        view.onDoubleClick = { [weak self] divider in self?.onEqualize?(divider.path) }
        addSubview(view)
        return view
    }
}
