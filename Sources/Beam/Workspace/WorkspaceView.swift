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
    /// The user dropped a pane's header onto another pane.
    var onMovePane: ((Pane.ID, Pane.ID, SplitTree.Drop) -> Void)?

    var style: GhosttyApp.SplitStyle {
        didSet { needsDisplay = true }
    }

    private var tree = SplitTree()
    private var dividers: [DividerView] = []
    private var paneViews: [PaneView] { subviews.compactMap { $0 as? PaneView } }
    private let dropPreview = DropPreview()
    /// Where the pane being dragged would land, while it is over another.
    private var pendingDrop: (pane: Pane.ID, target: Pane.ID, drop: SplitTree.Drop)?

    init(style: GhosttyApp.SplitStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        // Terminals take files and text, not panes, so a pane dragged over
        // one comes up the chain to here.
        registerForDraggedTypes([.beamPane])
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
            view.showsHeader = wanted.count > 1
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

    // MARK: Dropping a pane

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let frames = tree.layout(in: bounds, dividerThickness: Self.dividerThickness).frames
        guard
            let pane = sender.draggingPasteboard.string(forType: .beamPane)
                .flatMap(UUID.init(uuidString:)).map({ Pane.ID(uuid: $0) }),
            let (target, frame) = frames.first(where: { $0.value.contains(point) }).map({ ($0.key, $0.value) }),
            target != pane, tree.contains(pane)
        else {
            endDrop()
            return []
        }
        let drop = SplitTree.Drop(at: point, in: frame)
        if pendingDrop?.target != target || pendingDrop?.drop != drop {
            dropPreview.show(drop.preview(in: frame), in: self)
        }
        pendingDrop = (pane, target, drop)
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        endDrop()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let pendingDrop else { return false }
        endDrop()
        onMovePane?(pendingDrop.pane, pendingDrop.target, pendingDrop.drop)
        return true
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        endDrop()
    }

    private func endDrop() {
        pendingDrop = nil
        dropPreview.hide()
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

/// Shows where a dragged pane will land: a tinted, rounded outline of the
/// space it will take, which glides between places as the pointer moves.
private final class DropPreview: NSView {
    private static let inset = 4.0

    /// Whether it is on screen, fading out counting as gone.
    private var isShowing = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1.5
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Runs with this view's appearance current, so the accent colour resolves
    // for light or dark mode.
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
    }

    func show(_ frame: CGRect, in parent: NSView) {
        let target = frame.insetBy(dx: Self.inset, dy: Self.inset)
        // Above the panes and the dividers' grab areas.
        if parent.subviews.last !== self {
            parent.addSubview(self, positioned: .above, relativeTo: nil)
        }
        // It appears where the pane would land, then glides from place to place.
        if !isShowing {
            self.frame = target
            isShowing = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            animator().frame = target
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0
        }
    }
}
