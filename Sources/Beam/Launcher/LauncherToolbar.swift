import AppKit
import BeamCore

/// The title bar: the sidebar toggle, then at the trailing end a button
/// showing the Agents menu while an update waits, and a segmented control
/// with a segment for each installed agent and one for a plain shell.
/// Reports which entry was clicked; the window controller opens it.
final class LauncherToolbar: NSObject, NSToolbarDelegate {
    private static let leading: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
    ]
    private static let updatesIdentifier = NSToolbarItem.Identifier("Agent Updates")
    private static let launchersIdentifier = NSToolbarItem.Identifier("Launchers")

    let toolbar = NSToolbar(identifier: "Main")
    var onLaunch: ((LauncherEntry) -> Void)?
    /// What the update button opens.
    var updatesMenu = NSMenu()
    private var installed: Set<Agent> = []
    private var updates = 0
    /// The entries the toolbar's launcher segments stand for, in order.
    private var grouped: [LauncherEntry] = []

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    /// Shows a segment for each agent in `installed` and none for the rest,
    /// by rebuilding the control.
    func show(installed: Set<Agent>) {
        self.installed = installed
        reconcile()
    }

    /// Shows the update button while `count` updates wait.
    func show(updates count: Int) {
        updates = count
        let button = toolbar.items.first { $0.itemIdentifier == Self.updatesIdentifier }
        button?.title = updatesTitle
        reconcile()
    }

    private var updatesTitle: String { updates == 1 ? "1 Update" : "\(updates) Updates" }

    private func reconcile() {
        let wanted = shownIdentifiers
        guard toolbar.items.map(\.itemIdentifier) != wanted || grouped != shown else { return }
        while toolbar.items.count > Self.leading.count {
            toolbar.removeItem(at: toolbar.items.count - 1)
        }
        for identifier in wanted.dropFirst(Self.leading.count) {
            toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count)
        }
    }

    private var shown: [LauncherEntry] {
        LauncherEntry.all.filter { entry in
            guard case .agent(let agent) = entry else { return true }
            return installed.contains(agent)
        }
    }

    private var shownIdentifiers: [NSToolbarItem.Identifier] {
        Self.leading + (updates > 0 ? [Self.updatesIdentifier] : []) + [Self.launchersIdentifier]
    }

    @objc private func launch(_ sender: NSToolbarItemGroup) {
        guard grouped.indices.contains(sender.selectedIndex) else { return }
        onLaunch?(grouped[sender.selectedIndex])
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        shownIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.leading + [Self.updatesIdentifier, Self.launchersIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if identifier == Self.updatesIdentifier {
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.menu = updatesMenu
            item.title = updatesTitle
            item.label = "Updates"
            item.isBordered = true
            item.toolTip = "Update the agent CLIs that have a newer version"
            return item
        }
        guard identifier == Self.launchersIdentifier else { return nil }
        // One segmented control, so the launchers read as a single light
        // capsule in the title bar rather than a row of capsules.
        grouped = shown
        let group = NSToolbarItemGroup(
            itemIdentifier: identifier, titles: grouped.map(\.name), selectionMode: .momentary,
            labels: grouped.map(\.name), target: self, action: #selector(launch(_:)))
        group.label = "Open"
        group.toolTip = "Open an agent or a shell in a new pane in this workspace's folder"
        return group
    }
}
