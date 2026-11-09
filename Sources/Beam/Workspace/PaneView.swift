import AppKit
import BeamCore

/// One pane on screen: its terminal, a header while it shares the workspace
/// with other panes, and an overlay that dims the terminal while another
/// pane has focus.
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

    init(id: Pane.ID, terminal: TerminalView, style: GhosttyApp.SplitStyle) {
        self.id = id
        self.terminal = terminal
        overlay = Overlay(style: style)
        header = PaneHeaderView(style: style)
        super.init(frame: terminal.frame)
        header.isHidden = true
        addSubview(terminal)
        addSubview(overlay)
        addSubview(header)
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
        overlay.frame = content
    }

    private func updateHeaderTitle() {
        header.title = title ?? directory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
    }
}

/// Dims the terminal while another pane has focus, and lets every click
/// through to it.
private final class Overlay: NSView {
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
        layer?.backgroundColor =
            pane?.emphasis == .unfocused
            ? style.unfocusedFill.withAlphaComponent(style.unfocusedFillOpacity).cgColor
            : nil
    }
}
