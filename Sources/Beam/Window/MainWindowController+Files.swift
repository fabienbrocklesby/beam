import AppKit
import BeamCore
import os

// Files that panes name: links the user Cmd+clicks, and the files an
// agent's reply names, which the pane's tray previews.
extension MainWindowController {
    /// Where files are looked for on disk, in the order asked, so a turn's
    /// previews never land after the next turn's.
    private static let fileQueue = DispatchQueue(label: "dev.beam.terminal.files", qos: .userInitiated)

    /// Opens what a Cmd+clicked link in `pane` names: a web address in the
    /// user's browser, a file in its default app once `FileResolver` finds
    /// it from the pane's directory. A link to nothing beeps.
    func openLink(_ text: String, from pane: Pane.ID) {
        switch FileMention(text, home: NSHomeDirectory()) {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .file(let path):
            let directory = paneViews[pane]?.directory
            Self.fileQueue.async {
                let found = FileResolver.disk.path(for: path, directory: directory, touched: [])
                DispatchQueue.main.async {
                    guard let found else {
                        Logger.app.info("found no file for a link")
                        NSSound.beep()
                        return
                    }
                    NSWorkspace.shared.open(URL(filePath: found))
                }
            }
        case nil:
            NSSound.beep()
        }
    }

    /// Shows the files a finished turn's reply named in `pane`'s tray, once
    /// found on disk, replacing the last turn's. A reply that names none
    /// that can be previewed hides the tray.
    func showPreviews(of lookup: TurnFiles.Lookup, in pane: Pane.ID) {
        guard store.showsPreviews else { return }
        let home = NSHomeDirectory()
        Self.fileQueue.async { [weak self] in
            let found = FileResolver.disk.paths(
                for: lookup.names, directory: lookup.directory, touched: lookup.touched, home: home)
            let viewable = found.map { URL(filePath: $0) }.filter(PreviewTrayView.canPreview)
            let files = Array(viewable.prefix(PreviewTrayView.limit))
            DispatchQueue.main.async {
                // The pane may have closed, or previews been turned off.
                guard let self, self.store.showsPreviews, self.store.workspaceID(containing: pane) != nil else {
                    return
                }
                self.previews[pane] = files.isEmpty ? nil : files
                self.paneViews[pane]?.previews = files
            }
        }
    }

    @objc func toggleShowsPreviews(_ sender: Any?) {
        update { $0.showsPreviews.toggle() }
        guard !store.showsPreviews else { return }
        previews = [:]
        for view in paneViews.values { view.previews = [] }
    }
}
