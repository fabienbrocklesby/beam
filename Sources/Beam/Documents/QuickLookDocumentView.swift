import Quartz

/// Audio or video, played by Quick Look, which draws it out of process.
final class QuickLookDocumentView: NSView {
    private var preview: QLPreviewView?

    func show(_ url: URL) {
        if let preview, preview.previewItem?.previewItemURL == url {
            preview.refreshPreviewItem()
            return
        }
        preview?.removeFromSuperview()
        guard let preview = QLPreviewView(frame: bounds, style: .normal) else { return }
        preview.autoresizingMask = [.width, .height]
        preview.autostarts = false
        preview.previewItem = url as NSURL
        addSubview(preview)
        self.preview = preview
    }

    // A pane that closes frees its player now, not with the window.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        preview?.close()
        preview?.removeFromSuperview()
        preview = nil
    }

    // Clicks on the player focus the pane, for its keys.
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
