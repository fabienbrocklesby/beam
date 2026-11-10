import AppKit
import BeamCore

/// One pane on screen: its terminal, a header while it shares the workspace
/// with other panes, and an overlay that dims the terminal while another
/// pane has focus, and the whole pane while it is being dragged.
final class PaneView: NSView {
    enum Emphasis {
        /// The only pane on screen.
        case none
        case focused
        case unfocused
    }

    let id: Pane.ID
    let terminal: TerminalView
    /// The terminal's latest title, for the window title.
    var title: String? {
        didSet { updateHeaderTitle() }
    }
    /// The pane's directory, which names it until its terminal sets a title.
    var directory: String? {
        didSet { updateHeaderTitle() }
    }

    var emphasis = Emphasis.none {
        didSet {
            guard emphasis != oldValue else { return }
            overlay.needsDisplay = true
            header.isFocused = emphasis == .focused
        }
    }

    /// What the pane's agent last reported, for its header.
    var agent: AgentState? {
        get { header.agent }
        set { header.agent = newValue }
    }

    /// Whether the header shows, which it does while the workspace has
    /// other panes.
    var showsHeader = false {
        didSet {
            guard showsHeader != oldValue else { return }
            header.isHidden = !showsHeader
            layOutContent()
        }
    }

    var style: GhosttyApp.SplitStyle {
        get { overlay.style }
        set {
            overlay.style = newValue
            header.style = newValue
        }
    }

    private let overlay: Overlay
    private let header: PaneHeaderView
    /// Set while the pane is dragged by its header, so it reads as picked up.
    fileprivate private(set) var isLifted = false {
        didSet {
            overlay.needsDisplay = true
            layOutContent()
        }
    }

    init(id: Pane.ID, terminal: TerminalView, style: GhosttyApp.SplitStyle) {
        self.id = id
        self.terminal = terminal
        overlay = Overlay(style: style)
        header = PaneHeaderView(pane: id, style: style)
        super.init(frame: terminal.frame)
        header.isHidden = true
        addSubview(terminal)
        addSubview(header)
        // Over the header too, which it dims along with the terminal while
        // the pane is lifted. It lets every click through.
        addSubview(overlay)
        overlay.pane = self
        layOutContent()

        // The header acts through the same paths as the keyboard: focus by
        // making the terminal first responder, zoom and close by its
        // keybinding actions, so confirmation follows the user's config.
        header.onFocus = { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(terminal)
        }
        header.onToggleZoom = { [weak self] in self?.terminal.performBindingAction("toggle_split_zoom") }
        header.onClose = { [weak self] in self?.terminal.performBindingAction("close_surface") }
        header.onDragging = { [weak self] dragging in self?.isLifted = dragging }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layOutContent()
    }

    private func layOutContent() {
        var content = bounds
        if showsHeader {
            let (strip, rest) = bounds.divided(atDistance: min(PaneHeaderView.height, bounds.height), from: .maxYEdge)
            header.frame = strip
            content = rest
        }
        terminal.frame = content
        overlay.frame = isLifted ? bounds : content
    }

    private func updateHeaderTitle() {
        header.title = title ?? directory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
    }
}

/// Dims the terminal while another pane has focus, more strongly while the
/// pane is lifted, and lets every click through.
private final class Overlay: NSView {
    /// How strongly a lifted pane is covered, unless unfocused panes already
    /// are more.
    private static let liftedOpacity = 0.6

    weak var pane: PaneView?
    var style: GhosttyApp.SplitStyle {
        didSet { needsDisplay = true }
    }

    init(style: GhosttyApp.SplitStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        let opacity =
            pane?.isLifted == true
            ? max(style.unfocusedFillOpacity, Self.liftedOpacity)
            : pane?.emphasis == .unfocused ? style.unfocusedFillOpacity : 0
        layer?.backgroundColor = opacity > 0 ? style.unfocusedFill.withAlphaComponent(opacity).cgColor : nil
    }
}
