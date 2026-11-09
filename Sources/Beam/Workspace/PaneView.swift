import AppKit
import BeamCore

/// One pane on screen: its terminal, plus an overlay that dims it while
/// another pane has focus or edges it in the accent colour while it has focus.
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
    var title: String?

    var emphasis = Emphasis.none {
        didSet {
            guard emphasis != oldValue else { return }
            overlay.needsDisplay = true
        }
    }

    var style: GhosttyApp.SplitStyle {
        get { overlay.style }
        set { overlay.style = newValue }
    }

    private let overlay: Overlay

    init(id: Pane.ID, terminal: TerminalView, style: GhosttyApp.SplitStyle) {
        self.id = id
        self.terminal = terminal
        overlay = Overlay(style: style)
        super.init(frame: terminal.frame)
        terminal.autoresizingMask = [.width, .height]
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(terminal)
        addSubview(overlay)
        overlay.pane = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

/// Draws over the terminal and lets every click through to it.
private final class Overlay: NSView {
    private static let edgeWidth = 1.0

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

    // Runs with this view's appearance current, so the accent colour resolves
    // for light or dark mode.
    override func updateLayer() {
        guard let layer else { return }
        let emphasis = pane?.emphasis ?? .none
        layer.backgroundColor =
            emphasis == .unfocused
            ? style.unfocusedFill.withAlphaComponent(style.unfocusedFillOpacity).cgColor
            : nil
        layer.borderWidth = emphasis == .focused ? Self.edgeWidth : 0
        layer.borderColor = NSColor.controlAccentColor.cgColor
    }
}
