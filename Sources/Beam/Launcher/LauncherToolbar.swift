import AppKit
import BeamCore

/// The title bar: the sidebar toggle, then at the trailing end a button
/// showing the Agents menu while an update waits, a button for each
/// installed agent and one for a plain shell. Reports which entry was
/// clicked; the window controller opens it.
final class LauncherToolbar: NSObject, NSToolbarDelegate {
    private static let leading: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
    ]
    private static let updatesIdentifier = NSToolbarItem.Identifier("Agent Updates")

    let toolbar = NSToolbar(identifier: "Main")
    var onLaunch: ((LauncherEntry) -> Void)?
    /// What the update button opens.
    var updatesMenu = NSMenu()
    private var installed: Set<Agent> = []
    private var updates = 0

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    /// Shows a button for each agent in `installed` and none for the rest.
    /// Missing agents' items are removed rather than hidden, since hiding a
    /// toolbar item needs macOS 15.
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
        guard toolbar.items.map(\.itemIdentifier) != wanted else { return }
        while toolbar.items.count > Self.leading.count {
            toolbar.removeItem(at: toolbar.items.count - 1)
        }
        for identifier in wanted.dropFirst(Self.leading.count) {
            toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count)
        }
    }

    private var shownIdentifiers: [NSToolbarItem.Identifier] {
        let shown = LauncherEntry.all.filter { entry in
            guard case .agent(let agent) = entry else { return true }
            return installed.contains(agent)
        }
        return Self.leading + (updates > 0 ? [Self.updatesIdentifier] : []) + shown.map(Self.identifier)
    }

    private static func identifier(_ entry: LauncherEntry) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("Launch \(entry.name)")
    }

    @objc private func launch(_ sender: NSToolbarItem) {
        guard let entry = LauncherEntry.all.first(where: { Self.identifier($0) == sender.itemIdentifier }) else {
            return
        }
        onLaunch?(entry)
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        shownIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.leading + [Self.updatesIdentifier] + LauncherEntry.all.map(Self.identifier)
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
        guard let entry = LauncherEntry.all.first(where: { Self.identifier($0) == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.title = entry.name
        item.label = entry.name
        item.isBordered = true
        item.toolTip = "Open \(entry.name) in a new pane in this workspace's folder"
        item.target = self
        item.action = #selector(launch(_:))
        return item
    }
}
