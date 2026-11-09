import AppKit

extension NSPasteboard.PasteboardType {
    /// A pane being dragged to another place in its workspace: its ID.
    static let beamPane = Self("dev.beam.terminal.pane")
    /// A sidebar row being dragged to another position: its workspace's ID.
    static let beamWorkspace = Self("dev.beam.terminal.workspace")
}
