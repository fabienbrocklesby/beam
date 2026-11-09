import AppKit
import BeamCore

/// The Agents menu: each installed agent's version, how it was installed and
/// its update, then Update All and Check for Updates.
///
/// The menu bar and the title bar's update button each show one. They are
/// filled as they open and again while open, as versions come in, so opening
/// one never waits on a program or a registry.
final class AgentsMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let updates: AgentUpdates
    private var open: [NSMenu] = []
    /// Menus a pull-down button shows, which leave their first item out:
    /// the button stands in for it.
    private var pullDowns: Set<ObjectIdentifier> = []

    init(updates: AgentUpdates) {
        self.updates = updates
    }

    /// `pullDown` is for a menu shown from a pull-down button, such as the
    /// title bar's update button.
    func makeMenu(pullDown: Bool = false) -> NSMenu {
        let menu = NSMenu(title: "Agents")
        menu.delegate = self
        if pullDown { pullDowns.insert(ObjectIdentifier(menu)) }
        fill(menu)
        return menu
    }

    /// Brings the open menus up to date.
    func refresh() {
        for menu in open { fill(menu) }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updates.check()
    }

    /// The action of rows that only inform, so they validate as disabled. A
    /// pull-down button gives a row without an action its own, which would
    /// show it enabled.
    @objc private func inform(_ sender: Any?) {}

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(inform(_:))
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        fill(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        open.append(menu)
        updates.menuWillOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        open.removeAll { $0 === menu }
    }

    // MARK: Items

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        if pullDowns.contains(ObjectIdentifier(menu)) {
            menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        }
        let installed = Agent.allCases.compactMap { agent in updates.updates[agent].map { (agent, $0) } }
        if installed.isEmpty {
            let none = menu.addItem(
                withTitle: updates.hasLooked ? "No Agents Found" : "Finding Agents…", action: #selector(inform(_:)),
                keyEquivalent: "")
            none.target = self
        }
        for (agent, update) in installed { menu.addItem(item(for: agent, update)) }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Update All", action: #selector(MainWindowController.updateAllAgents(_:)), keyEquivalent: "")
        let check = menu.addItem(
            withTitle: updates.isChecking ? "Checking for Updates…" : "Check for Updates",
            action: updates.isChecking ? #selector(inform(_:)) : #selector(checkForUpdates(_:)), keyEquivalent: "")
        check.target = self
    }

    /// "Update Claude to 2.1.319" when an update waits, which runs it, or
    /// else "Claude 2.1.319", with how it was installed beneath.
    private func item(for agent: Agent, _ update: AgentUpdate) -> NSMenuItem {
        let item: NSMenuItem
        if let available = update.available {
            item = NSMenuItem(
                title: "Update \(agent.name) to \(available)",
                action: #selector(MainWindowController.updateAgent(_:)), keyEquivalent: "")
            item.representedObject = agent
        } else {
            let title = [agent.name, update.installed?.description].compactMap { $0 }.joined(separator: " ")
            item = NSMenuItem(title: title, action: #selector(inform(_:)), keyEquivalent: "")
            item.target = self
        }
        var detail = [status(of: update), update.method.map { "installed with \($0.name)" }].compactMap { $0 }
            .joined(separator: ", ")
        detail = detail.prefix(1).uppercased() + detail.dropFirst()
        let outdated = updates.outdatedPanes(of: agent)
        if outdated > 0, let version = update.outdatedVersion {
            detail +=
                "\n\(outdated == 1 ? "1 pane still runs" : "\(outdated) panes still run") \(version) until restarted"
        }
        if #available(macOS 14.4, *) {
            item.subtitle = detail
        } else {
            item.toolTip = detail
        }
        return item
    }

    private func status(of update: AgentUpdate) -> String? {
        guard update.method != nil else { return "installed some way Beam cannot update" }
        guard let installed = update.installed else { return "version unknown" }
        if update.available != nil { return installed.description }
        switch update.latest {
        case .found: return "up to date"
        case .failed: return updates.isChecking ? "checking for updates" : "could not check for updates"
        case .unknown: return updates.isChecking ? "checking for updates" : nil
        }
    }
}
