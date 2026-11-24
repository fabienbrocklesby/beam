import AppKit
import BeamCore

// The conversations Claude Code keeps for the selected workspace's folder.
extension MainWindowController {
    /// Where session files are read, off the main thread.
    private static let historyQueue = DispatchQueue(label: "dev.beam.terminal.history", qos: .userInitiated)

    /// Shell > Resume Conversation…: opens the switcher on the selected
    /// workspace's past conversations, newest first, or closes it. Picking
    /// one opens it in a pane (see `WorkspaceStore.resume`).
    @objc func showConversations(_ sender: Any?) {
        guard switcher == nil else {
            closeSwitcher()
            return
        }
        guard let workspace = store.selectedWorkspace else { return }
        let (id, folder) = (workspace.id, workspace.folder)
        let history = ClaudeHistory(home: NSHomeDirectory())
        Self.historyQueue.async { [weak self] in
            let conversations = history.conversations(in: folder)
            DispatchQueue.main.async { self?.show(conversations, of: id) }
        }
    }

    private func show(_ conversations: [Conversation], of id: Workspace.ID) {
        // The user may have moved on while the files were read.
        guard switcher == nil, store.selection == id, let workspace = store.workspace(id) else { return }
        let ages = RelativeDateTimeFormatter()
        ages.dateTimeStyle = .named
        let now = Date()
        let items = conversations.map { conversation in
            // One from a folder inside the workspace's says which.
            let name = workspace.relativeName(of: conversation.folder)
            let folder = name == workspace.name ? nil : name
            // Never in the future, whatever the clock did since.
            let age = ages.localizedString(for: min(conversation.modified, now), relativeTo: now)
            return SwitcherViewController.Item(
                target: .conversation(conversation), title: conversation.title,
                detail: [folder, age].compactMap(\.self).joined(separator: " · "), symbol: "bubble.left")
        }
        let placeholder =
            items.isEmpty
            ? "No Claude conversations in \(workspace.name) yet" : "Resume a conversation in \(workspace.name)"
        showSwitcher(items, placeholder: placeholder)
    }
}
