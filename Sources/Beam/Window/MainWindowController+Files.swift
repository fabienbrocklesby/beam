import AppKit
import BeamCore
import os

// Files that panes name: links the user Cmd+clicks, and the files an
// agent's reply names, which the pane's tray previews. And files and
// folders opened from Finder or the Open panel.
extension MainWindowController {
    /// Where files are looked for on disk, in the order asked, so a turn's
    /// previews never land after the next turn's.
    private static let fileQueue = DispatchQueue(label: "dev.beam.terminal.files", qos: .userInitiated)

    /// Opens what a Cmd+clicked link in `pane` names: a web address in the
    /// user's browser, a file once `FileResolver` finds it from the pane's
    /// directory as `show(_:kind:from:)` does. A link to nothing beeps.
    func openLink(_ text: String, from pane: Pane.ID) {
        switch FileMention(text, home: NSHomeDirectory()) {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .file(let path):
            let directory = paneViews[pane]?.directory
            Self.fileQueue.async { [weak self] in
                let found = FileResolver.disk.path(for: path, directory: directory, touched: [])
                let kind = found.map { DocumentKind(file: URL(filePath: $0), chosen: false) }
                DispatchQueue.main.async {
                    guard let found, let kind else {
                        Logger.app.info("found no file for a link")
                        NSSound.beep()
                        return
                    }
                    self?.show(URL(filePath: found), kind: kind, from: pane)
                }
            }
        case nil:
            NSSound.beep()
        }
    }

    /// Shows a file clicked in `pane`'s tray as `show(_:kind:from:)` does.
    func showFile(_ url: URL, from pane: Pane.ID) {
        Self.fileQueue.async { [weak self] in
            let kind = DocumentKind(file: url, chosen: false)
            DispatchQueue.main.async { self?.show(url, kind: kind, from: pane) }
        }
    }

    /// Shows a file `pane` named in its workspace's viewer, focus staying in
    /// `pane`, or opens it in its app when Beam leaves its kind to one:
    /// source code goes to the user's editor.
    private func show(_ url: URL, kind: DocumentKind, from pane: Pane.ID) {
        update { store in
            store.focus(pane)
            if kind != .external { store.showDocument(url.path, from: pane) }
        }
        if kind == .external { openOutsideBeam(url) }
    }

    /// Opens a file in its app outside Beam, as a double-click in a tray
    /// does. Never through `open(_:)`: source code is plain text, so once
    /// Beam opens plain text the file would come straight back.
    func openOutsideBeam(_ url: URL) {
        Self.fileQueue.async {
            let app = NSWorkspace.shared.applicationOutsideBeam(toOpen: url)
            DispatchQueue.main.async {
                guard let app else {
                    Logger.app.info("found no app for a file")
                    NSSound.beep()
                    return
                }
                NSWorkspace.shared.open(
                    [url], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    /// Opens a file a link in document `pane` names: in that pane when Beam
    /// shows its kind, else in its app. A link to nothing beeps.
    func openLinkedFile(_ url: URL, from pane: Pane.ID) {
        let url = url.standardizedFileURL
        Self.fileQueue.async { [weak self] in
            let exists = FileManager.default.fileExists(atPath: url.path)
            let kind = DocumentKind(file: url, chosen: false)
            DispatchQueue.main.async {
                guard exists else {
                    Logger.app.info("found no file for a link")
                    NSSound.beep()
                    return
                }
                guard kind != .external else {
                    self?.openOutsideBeam(url)
                    return
                }
                self?.update { $0.updatePane(pane) { $0.document = url.path } }
            }
        }
    }

    /// Opens files and folders as Finder asks: a folder as its workspace, a
    /// file as `WorkspaceStore.openDocument(_:)` does. The last one ends up
    /// selected.
    func open(_ items: [(url: URL, isFolder: Bool)]) {
        update { store in
            for item in items {
                if item.isFolder { store.open(folder: item.url.path) } else { store.openDocument(item.url.path) }
            }
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
