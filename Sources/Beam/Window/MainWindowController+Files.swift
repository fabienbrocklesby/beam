import AppKit
import BeamCore
import os

// Files that panes name: links the user Cmd+clicks.
extension MainWindowController {
    /// Opens what a Cmd+clicked link in `pane` names: a web address in the
    /// user's browser, a file in its default app once `FileResolver` finds
    /// it from the pane's directory. A link to nothing beeps.
    func openLink(_ text: String, from pane: Pane.ID) {
        switch FileMention(text, home: NSHomeDirectory()) {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .file(let path):
            let directory = paneViews[pane]?.directory
            DispatchQueue.global(qos: .userInitiated).async {
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
}
