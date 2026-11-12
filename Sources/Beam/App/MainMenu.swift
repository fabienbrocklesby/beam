import AppKit

/// The menu bar. Terminal items run a Ghostty keybinding action on the
/// focused pane, so a click and its key take one path, and each shows the key
/// the user's Ghostty config actually binds to that action.
enum MainMenu {
    static func make(ghostty: GhosttyApp, agents: AgentsMenu) -> NSMenu {
        /// Shows the key the user's config binds to `action`, if any.
        func boundKey(_ item: NSMenuItem, _ action: String) -> NSMenuItem {
            if let key = ghostty.keyEquivalent(for: action) {
                item.keyEquivalent = key.key
                item.keyEquivalentModifierMask = key.modifiers
            }
            return item
        }

        func binding(_ title: String, _ action: String, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(
                title: title, action: #selector(MainWindowController.performBindingAction(_:)), keyEquivalent: "")
            item.representedObject = action
            item.tag = tag
            return boundKey(item, action)
        }

        // App-wide, so they work with no pane focused. Ghostty binds Cmd+,
        // and Cmd+Shift+, to these by default.
        func appItem(_ title: String, _ selector: Selector, _ action: String) -> NSMenuItem {
            boundKey(NSMenuItem(title: title, action: selector, keyEquivalent: ""), action)
        }

        let app = NSMenu(title: "Beam")
        app.addItem(
            withTitle: "About Beam", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(appItem("Settings…", #selector(AppDelegate.openSettings(_:)), "open_config"))
        app.addItem(appItem("Reload Configuration", #selector(AppDelegate.reloadConfiguration(_:)), "reload_config"))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Beam", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"
        ).keyEquivalentModifierMask = [.command, .option]
        app.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        // Quit Beam leaves every session running; this ends them first.
        app.addItem(withTitle: "Quit Beam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.addItem(
            withTitle: "Quit and End Sessions", action: #selector(AppDelegate.quitAndEndSessions(_:)), keyEquivalent: ""
        )

        let shell = NSMenu(title: "Shell")
        shell.addItem(binding("New Workspace…", "new_tab"))
        shell.addItem(.separator())
        for entry in LauncherEntry.all {
            let item = NSMenuItem(
                title: entry.title, action: #selector(MainWindowController.openLauncherEntry(_:)), keyEquivalent: "")
            item.representedObject = entry
            shell.addItem(item)
        }
        shell.addItem(.separator())
        shell.addItem(binding("Split Right", "new_split:right"))
        shell.addItem(binding("Split Down", "new_split:down"))
        shell.addItem(.separator())
        shell.addItem(binding("Close", "close_surface"))
        shell.addItem(binding("Close Workspace", "close_tab:this"))

        // Along the responder chain rather than run on the focused pane, so a
        // terminal, a document and a text field each answer in their own way.
        // Ghostty binds Cmd+C, Cmd+V and Cmd+F as performable, and reports no
        // such key for a menu, so these start from the macOS keys.
        func editItem(_ title: String, _ selector: Selector, _ action: String, _ key: String) -> NSMenuItem {
            boundKey(NSMenuItem(title: title, action: selector, keyEquivalent: key), action)
        }
        let edit = NSMenu(title: "Edit")
        edit.addItem(editItem("Copy", #selector(NSText.copy(_:)), "copy_to_clipboard", "c"))
        edit.addItem(editItem("Paste", #selector(NSText.paste(_:)), "paste_from_clipboard", "v"))
        edit.addItem(editItem("Select All", #selector(NSResponder.selectAll(_:)), "select_all", "a"))
        edit.addItem(.separator())
        let find = editItem("Find…", #selector(NSResponder.performTextFinderAction(_:)), "start_search", "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)

        let view = NSMenu(title: "View")
        view.addItem(
            withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s"
        ).keyEquivalentModifierMask = [.command, .control]
        view.addItem(.separator())
        view.addItem(binding("Zoom Split", "toggle_split_zoom"))
        view.addItem(binding("Equalize Splits", "equalize_splits"))
        view.addItem(.separator())
        view.addItem(
            withTitle: "Show Archived Workspaces", action: #selector(MainWindowController.toggleShowsArchived(_:)),
            keyEquivalent: "")
        view.addItem(
            withTitle: "Show File Previews", action: #selector(MainWindowController.toggleShowsPreviews(_:)),
            keyEquivalent: "")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(
            withTitle: "Go to Workspace or Pane…", action: #selector(MainWindowController.toggleSwitcher(_:)),
            keyEquivalent: "p")
        // Cmd+J and Cmd+Shift+J are Ghostty's.
        window.addItem(
            withTitle: "Next Agent Needing You",
            action: #selector(MainWindowController.goToNextAgentNeedingUser(_:)), keyEquivalent: "u"
        ).keyEquivalentModifierMask = [.command, .shift]
        window.addItem(.separator())
        // Titled with workspace names when the menu validates.
        for position in 1...8 {
            window.addItem(binding("Workspace \(position)", "goto_tab:\(position)", tag: position))
        }
        window.addItem(binding("Last Workspace", "last_tab"))
        window.addItem(binding("Previous Workspace", "previous_tab"))
        window.addItem(binding("Next Workspace", "next_tab"))
        window.addItem(.separator())
        NSApp.windowsMenu = window

        let main = NSMenu()
        for menu in [app, shell, edit, view, agents.makeMenu(), window] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}
