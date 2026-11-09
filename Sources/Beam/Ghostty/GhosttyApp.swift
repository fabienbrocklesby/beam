import AppKit
import BeamCore
import GhosttyKit
import os

/// Owns the process-wide libghostty app and config, and routes libghostty's
/// runtime callbacks to the right terminal view. Create exactly one, before
/// any `TerminalView`.
///
/// Threading, established from vendor/ghostty/src/App.zig and
/// src/apprt/embedded.zig at v1.4.0: `wakeup` arrives on any thread, because the
/// IO and renderer threads call it whenever they post to the app mailbox. Every
/// other callback runs synchronously on the main thread, inside
/// `ghostty_app_tick` or inside one of our own `ghostty_surface_*` calls, so
/// those assert main-actor isolation instead of hopping.
///
/// Callback shapes follow Ghostty's own macOS app (MIT, see NOTICE).
final class GhosttyApp {
    private(set) var app: ghostty_app_t?
    /// The config as libghostty last applied it, with the light or dark half
    /// of a `theme = light:...,dark:...` chosen. Replaced on every change.
    private(set) var config: ghostty_config_t
    /// Called after the config changes: a reload, or macOS switching between
    /// light and dark.
    var onConfigChange: (() -> Void)?
    private var appearanceObservation: NSKeyValueObservation?

    /// Returns nil if libghostty cannot start; the reason is logged.
    init?() {
        // libghostty snapshots the process environment here, so anything that
        // edits the environment for child processes must run before this.
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            Logger.ghostty.fault("ghostty_init failed")
            return nil
        }
        guard let config = Self.loadConfig() else {
            Logger.ghostty.fault("ghostty_config_new failed")
            return nil
        }
        self.config = config

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            // Sendable, so it does not inherit this initializer's main-actor
            // isolation: libghostty calls it from its IO and renderer threads.
            wakeup_cb: { @Sendable userdata in GhosttyApp.wakeup(userdata) },
            action_cb: { app, target, action in
                MainActor.assumeIsolated { GhosttyApp.perform(action, target: target, app: app) }
            },
            read_clipboard_cb: { userdata, location, state, mimes, mimesLength, list in
                MainActor.assumeIsolated {
                    GhosttyApp.readClipboard(
                        userdata, location: location, state: state, mimes: mimes, mimesLength: mimesLength,
                        list: list)
                }
            },
            confirm_read_clipboard_cb: { userdata, confirm, state, request in
                MainActor.assumeIsolated {
                    GhosttyApp.confirmReadClipboard(userdata, confirm: confirm, state: state, request: request)
                }
            },
            write_clipboard_cb: { userdata, location, content, length, confirm in
                MainActor.assumeIsolated {
                    GhosttyApp.writeClipboard(
                        userdata, location: location, content: content, length: length, confirm: confirm)
                }
            },
            close_surface_cb: { userdata, processAlive in
                MainActor.assumeIsolated { GhosttyApp.closeSurface(userdata, processAlive: processAlive) }
            }
        )

        guard let app = ghostty_app_new(&runtime, config) else {
            Logger.ghostty.fault("ghostty_app_new failed")
            return nil
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
        observeApplication()
    }

    isolated deinit {
        if let app { ghostty_app_free(app) }
        ghostty_config_free(config)
    }

    /// Beam's defaults, then the user's Ghostty config, then Beam's own
    /// settings file, then CLI flags (e.g. --command=claude). Each wins over
    /// the ones before, so Ghostty themes and fonts carry over and the
    /// settings file can change Beam alone. Returns nil only when libghostty
    /// cannot allocate a config; problems in the files are logged.
    private static func loadConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        if let defaults = Bundle.main.url(forResource: "defaults", withExtension: "ghostty") {
            ghostty_config_load_file(config, defaults.path)
        }
        ghostty_config_load_default_files(config)
        let settings = SettingsFile.standard.url.path
        if FileManager.default.fileExists(atPath: settings) {
            ghostty_config_load_file(config, settings)
        }
        ghostty_config_load_cli_args(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        for index in 0..<ghostty_config_diagnostics_count(config) {
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            Logger.ghostty.warning("config: \(String(cString: diagnostic.message), privacy: .public)")
        }
        return config
    }

    /// Reads every config file again and applies the result to every pane.
    func reloadConfig() {
        guard let app, let fresh = Self.loadConfig() else { return }
        // libghostty answers with GHOSTTY_ACTION_CONFIG_CHANGE before this
        // returns, and `adopt` keeps a copy of what it applied.
        ghostty_app_update_config(app, fresh)
        ghostty_config_free(fresh)
    }

    /// Opens Beam's settings file in the user's text editor, creating it first
    /// if there is none.
    func openSettings() {
        let file = SettingsFile.standard
        do {
            try file.createIfMissing()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Beam could not create its settings file."
            alert.runModal()
            return
        }
        // A .ghostty file has no editor unless the user picked one, so fall
        // back to their plain text editor.
        let workspace = NSWorkspace.shared
        guard
            let editor = workspace.urlForApplication(toOpen: file.url)
                ?? workspace.urlForApplication(toOpen: .plainText)
        else {
            Logger.ghostty.error("no text editor to open \(file.url.path, privacy: .public)")
            return
        }
        workspace.open([file.url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    private func observeApplication() {
        // Observers are never removed: this object lives as long as the process.
        let center = NotificationCenter.default
        let observations: [(Notification.Name, @MainActor (ghostty_app_t) -> Void)] = [
            (NSApplication.didBecomeActiveNotification, { ghostty_app_set_focus($0, true) }),
            (NSApplication.didResignActiveNotification, { ghostty_app_set_focus($0, false) }),
            (NSTextInputContext.keyboardSelectionDidChangeNotification, { ghostty_app_keyboard_changed($0) }),
        ]
        for (name, apply) in observations {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let app = self?.app { apply(app) }
                }
            }
        }

        // The app's scheme picks the theme half for the app-wide config, which
        // Beam's own chrome reads. Each TerminalView reports its own for its
        // pane. AppKit changes the appearance on the main thread.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) {
            [weak self] application, _ in
            MainActor.assumeIsolated {
                guard let app = self?.app else { return }
                ghostty_app_set_color_scheme(app, application.effectiveAppearance.ghosttyColorScheme)
            }
        }
    }

    /// Takes libghostty's applied config as Beam's own. libghostty frees
    /// `applied` once the action returns, so this keeps a copy.
    private func adopt(_ applied: ghostty_config_t) {
        guard let copy = ghostty_config_clone(applied) else { return }
        ghostty_config_free(config)
        config = copy
        onConfigChange?()
    }

    /// Applies the config again without reading the files, after the light
    /// or dark scheme changed for the app or one pane.
    private func reapplyConfig(to target: ghostty_target_s) {
        switch target.tag {
        case GHOSTTY_TARGET_APP:
            if let app { ghostty_app_update_config(app, config) }
        case GHOSTTY_TARGET_SURFACE:
            if let surface = target.target.surface { ghostty_surface_update_config(surface, config) }
        default:
            break
        }
    }

    private func tick() {
        if let app { ghostty_app_tick(app) }
    }

    // MARK: Callbacks

    private nonisolated static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async { app.tick() }
    }

    private static func perform(_ action: ghostty_action_s, target: ghostty_target_s, app: ghostty_app_t?) -> Bool {
        let view = target.tag == GHOSTTY_TARGET_SURFACE ? TerminalView.from(surface: target.target.surface) : nil
        let ghostty = ghostty_app_userdata(app).map { Unmanaged<GhosttyApp>.fromOpaque($0).takeUnretainedValue() }
        let payload = action.action

        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            NSApp.terminate(nil)
            return true

        // Soft reloads follow a light or dark switch: libghostty already has
        // the config and only needs it applied again for the new scheme.
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            guard let ghostty else { return false }
            if payload.reload_config.soft {
                ghostty.reapplyConfig(to: target)
            } else {
                ghostty.reloadConfig()
            }
            return true

        // Only the app-wide config is kept: Beam's chrome reads nothing per pane.
        case GHOSTTY_ACTION_CONFIG_CHANGE:
            guard target.tag == GHOSTTY_TARGET_APP, let ghostty, let applied = payload.config_change.config else {
                return false
            }
            ghostty.adopt(applied)
            return true

        case GHOSTTY_ACTION_OPEN_CONFIG:
            ghostty?.openSettings()
            return ghostty != nil

        case GHOSTTY_ACTION_SET_TITLE:
            guard let title = payload.set_title.title else { return false }
            return view?.send(.titleChanged(String(cString: title))) ?? false

        case GHOSTTY_ACTION_PWD:
            guard let pwd = payload.pwd.pwd else { return false }
            return view?.send(.workingDirectoryChanged(String(cString: pwd))) ?? false

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            return view?.send(.commandFinished) ?? false

        case GHOSTTY_ACTION_CELL_SIZE:
            guard let view else { return false }
            view.cellSize = NSSize(
                width: Double(payload.cell_size.width) / view.backingScale,
                height: Double(payload.cell_size.height) / view.backingScale)
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            view?.setCursorShape(payload.mouse_shape)
            return true

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            if payload.mouse_visibility == GHOSTTY_MOUSE_HIDDEN {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
            return true

        case GHOSTTY_ACTION_NEW_SPLIT:
            guard let direction = SplitTree.Direction(payload.new_split) else { return false }
            return view?.send(.newSplit(direction)) ?? false

        case GHOSTTY_ACTION_GOTO_SPLIT:
            guard let target = TerminalEvent.SplitTarget(payload.goto_split) else { return false }
            return view?.send(.focusSplit(target)) ?? false

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            return view?.send(.toggleSplitZoom) ?? false

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            return view?.send(.equalizeSplits) ?? false

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            guard let direction = SplitTree.Direction(payload.resize_split.direction) else { return false }
            return view?.send(.resizeSplit(direction, points: Double(payload.resize_split.amount))) ?? false

        // Beam has one window, and a workspace is what a tab or window would be.
        case GHOSTTY_ACTION_NEW_TAB, GHOSTTY_ACTION_NEW_WINDOW:
            return view?.send(.newWorkspace) ?? false

        case GHOSTTY_ACTION_GOTO_TAB:
            return view?.send(.selectWorkspace(TerminalEvent.WorkspaceTarget(payload.goto_tab))) ?? false

        case GHOSTTY_ACTION_CLOSE_TAB:
            guard payload.close_tab_mode == GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS else { return false }
            return view?.send(.closeWorkspace) ?? false

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            return view?.send(.closeWindow) ?? false

        default:
            return false
        }
    }

    private static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        guard let view = TerminalView.from(userdata: userdata) else { return }
        // libghostty calls this from inside the surface's own message handler,
        // so freeing the surface now would free memory still on its stack. The
        // next main-loop turn is the first point where that is safe.
        DispatchQueue.main.async { view.send(.closeRequested(processAlive: processAlive)) }
    }

    // MARK: Clipboard

    private struct ClipboardContent {
        let mime: String
        let data: Data
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?,
        mimes: UnsafePointer<UnsafePointer<CChar>?>?,
        mimesLength: Int,
        list: Bool
    ) -> ghostty_clipboard_read_result_e {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
            let mimes,
            let surface = TerminalView.from(userdata: userdata)?.surface
        else {
            return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED
        }

        let pasteboard = NSPasteboard.general
        var contents: [ClipboardContent] = []
        var seen = Set<String>()
        for index in 0..<mimesLength {
            guard let pointer = mimes[index] else { continue }
            let mime = String(cString: pointer)
            guard seen.insert(mime).inserted, let data = pasteboard.data(forMIMEType: mime) else { continue }
            contents.append(ClipboardContent(mime: mime, data: data))
        }
        let available = list ? pasteboard.availableMIMETypes() : []
        if contents.isEmpty && !list { return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE }

        completeClipboardRequest(surface, contents: contents, available: available, state: state)
        return GHOSTTY_CLIPBOARD_READ_STARTED
    }

    /// libghostty asks for this when a read needs consent, such as a paste that
    /// could run commands or a program reading the clipboard over OSC 52.
    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let view = TerminalView.from(userdata: userdata), let surface = view.surface else { return }
        guard let confirm else {
            ghostty_surface_deny_clipboard_request(surface, state)
            return
        }

        // The confirmation's buffers are only borrowed for this call, so copy them.
        let confirmation = confirm.pointee
        var contents: [ClipboardContent] = []
        if let list = confirmation.contents {
            for index in 0..<confirmation.contents_len {
                let item = list[index]
                let data = item.len > 0 ? Data(bytes: item.data, count: item.len) : Data()
                contents.append(ClipboardContent(mime: String(cString: item.mime), data: data))
            }
        }
        var available: [String] = []
        if let list = confirmation.available {
            for index in 0..<confirmation.available_len {
                if let pointer = list[index] { available.append(String(cString: pointer)) }
            }
        }

        let preview =
            contents.first { $0.mime == "text/plain" }
            .flatMap { String(data: $0.data, encoding: .utf8) } ?? ""

        let alert = NSAlert()
        alert.messageText =
            request == GHOSTTY_CLIPBOARD_REQUEST_PASTE
            ? "Paste text that may run commands?"
            : "A program wants to read your clipboard."
        alert.informativeText = String(preview.prefix(500))
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")

        let finish = { (response: NSApplication.ModalResponse) in
            guard let surface = view.surface else { return }
            if response == .alertFirstButtonReturn {
                completeClipboardRequest(
                    surface, contents: contents, available: available, state: state, confirmed: true)
            } else {
                ghostty_surface_deny_clipboard_request(surface, state)
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        length: Int,
        confirm: Bool
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD, let content, length > 0 else { return }

        // Writes that need consent come from programs (OSC 52), not the user.
        // Beam has no prompt for them, so it refuses rather than writes silently.
        guard !confirm else {
            Logger.ghostty.info("refused unconfirmed clipboard write from a program")
            return
        }

        let items = (0..<length).map { index in
            ClipboardContent(
                mime: String(cString: content[index].mime),
                data: Data(bytes: content[index].data, count: content[index].len))
        }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes(items.compactMap { NSPasteboard.PasteboardType(mimeType: $0.mime) }, owner: nil)
        for item in items {
            guard let type = NSPasteboard.PasteboardType(mimeType: item.mime) else { continue }
            pasteboard.setData(item.data, forType: type)
        }
    }

    private static func completeClipboardRequest(
        _ surface: ghostty_surface_t,
        contents: [ClipboardContent],
        available: [String],
        state: UnsafeMutableRawPointer?,
        confirmed: Bool = false
    ) {
        // libghostty borrows everything only for the duration of the call.
        CBorrowScope.with { scope in
            let cContents = contents.map { entry in
                ghostty_clipboard_content_s(
                    mime: scope.copy(entry.mime), data: scope.copy(entry.data), len: entry.data.count)
            }
            let cAvailable: [UnsafePointer<CChar>?] = available.map { scope.copy($0) }
            cContents.withUnsafeBufferPointer { contentsBuffer in
                cAvailable.withUnsafeBufferPointer { availableBuffer in
                    var complete = ghostty_clipboard_complete_s(
                        contents: contentsBuffer.baseAddress,
                        contents_len: contentsBuffer.count,
                        available: availableBuffer.baseAddress,
                        available_len: availableBuffer.count,
                        confirmed: confirmed,
                        remember: false)
                    ghostty_surface_complete_clipboard_request(surface, &complete, state)
                }
            }
        }
    }
}
