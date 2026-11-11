import AppKit
import BeamCore
import Quartz

/// One pane on screen: its terminal, a header while it shares the workspace
/// with other panes, a tray below while its agent's last reply named files
/// to preview, and an overlay that dims the terminal while another pane has
/// focus, and the whole pane while it is being dragged.
final class PaneView: NSView {
    enum Emphasis {
        /// The only pane on screen.
        case none
        case focused
        case unfocused
    }

    let id: Pane.ID
    let terminal: TerminalView
    /// The terminal's latest title.
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
            tray?.style = newValue
        }
    }

    /// The files the tray shows. None hides the tray, which frees it and
    /// its thumbnails.
    var previews: [URL] = [] {
        didSet {
            guard previews != oldValue else { return }
            showPreviews()
        }
    }
    /// Called when the user closes the tray.
    var onClosePreviews: (() -> Void)?

    private let overlay: Overlay
    private let header: PaneHeaderView
    private var tray: PreviewTrayView?
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
        overlay.frame = isLifted ? bounds : content
        if let tray {
            let (strip, rest) = content.divided(
                atDistance: min(PreviewTrayView.height, content.height), from: .minYEdge)
            tray.frame = strip
            content = rest
        }
        terminal.frame = content
    }

    /// What names the pane in its header and the window's subtitle.
    var displayTitle: String {
        title ?? directory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""
    }

    private func updateHeaderTitle() {
        header.title = displayTitle
    }

    // MARK: Previews

    private func showPreviews() {
        if previews.isEmpty {
            if controlsQuickLook { QLPreviewPanel.shared()?.orderOut(nil) }
            tray?.removeFromSuperview()
            tray = nil
        } else {
            let tray = self.tray ?? makeTray()
            tray.files = previews
            if controlsQuickLook { QLPreviewPanel.shared()?.reloadData() }
        }
        layOutContent()
    }

    private func makeTray() -> PreviewTrayView {
        let tray = PreviewTrayView(style: style)
        tray.onPreview = { [weak self] index in self?.showQuickLook(at: index) }
        tray.onOpen = { [weak self] index in self?.open(at: index) }
        tray.onClose = { [weak self] in
            self?.previews = []
            self?.onClosePreviews?()
        }
        // Under the overlay, which dims it with the terminal.
        addSubview(tray, positioned: .below, relativeTo: overlay)
        self.tray = tray
        return tray
    }

    private func open(at index: Int) {
        guard previews.indices.contains(index) else { return }
        if controlsQuickLook { QLPreviewPanel.shared()?.orderOut(nil) }
        NSWorkspace.shared.open(previews[index])
    }

    // MARK: Quick Look

    /// Whether the Quick Look panel is showing this pane's files.
    private var controlsQuickLook: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.currentController as AnyObject? === self
    }

    /// Shows `previews[index]` in the Quick Look panel, or hides the panel
    /// if it already shows it.
    private func showQuickLook(at index: Int) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, controlsQuickLook, panel.currentPreviewItemIndex == index {
            panel.orderOut(nil)
            return
        }
        // The panel takes the first controller up the responder chain from
        // the key window's first responder, which this pane's terminal
        // becomes. It focuses the pane, as any click in it does.
        window?.makeFirstResponder(terminal)
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = index
    }

    // Quick Look asks for a controller, and hands control over, on the
    // main thread.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel?) -> Bool {
        MainActor.assumeIsolated { !previews.isEmpty }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = self
            panel?.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel?) {
        MainActor.assumeIsolated {
            panel?.dataSource = nil
            panel?.delegate = nil
        }
    }
}

// Quick Look calls its data source and delegate on the main thread.
extension PaneView: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel?) -> Int {
        previews.count
    }

    func previewPanel(_ panel: QLPreviewPanel?, previewItemAt index: Int) -> (any QLPreviewItem)? {
        previews.indices.contains(index) ? previews[index] as NSURL : nil
    }

    /// The panel zooms out of the item's chip.
    func previewPanel(_ panel: QLPreviewPanel?, sourceFrameOnScreenFor item: (any QLPreviewItem)?) -> NSRect {
        guard let index = index(of: item), let chip = tray?.chip(at: index), let window = chip.window else {
            return .zero
        }
        return window.convertToScreen(chip.convert(chip.bounds, to: nil))
    }

    func previewPanel(
        _ panel: QLPreviewPanel?, transitionImageFor item: (any QLPreviewItem)?,
        contentRect: UnsafeMutablePointer<NSRect>?
    ) -> Any? {
        index(of: item).flatMap { tray?.thumbnail(at: $0) }
    }

    private func index(of item: (any QLPreviewItem)?) -> Int? {
        guard let url = item?.previewItemURL else { return nil }
        return previews.firstIndex(of: url)
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
