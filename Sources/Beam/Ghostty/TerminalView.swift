import AppKit
import Carbon
import GhosttyKit
import os

/// One terminal surface. libghostty owns the pty, the terminal state and the
/// Metal renderer; this view feeds it input, size and focus. Under beamd the
/// pty's far end is beam-attach, which pumps it to the pane's session.
///
/// Keyboard, IME and mouse handling is ported from Ghostty's SurfaceView_AppKit
/// (MIT, see NOTICE). Those paths are subtle (dead keys, Korean/Japanese IMEs,
/// option-as-alt, command bindings), so they stay close to upstream on purpose.
final class TerminalView: NSView {
    struct Options {
        /// A shell command the terminal runs instead of the user's login
        /// shell.
        var command: String?
        var workingDirectory: String?
        /// Written to the shell as it starts, as if typed.
        var initialInput: String?
        var environment: [String: String] = [:]
    }

    private(set) var surface: ghostty_surface_t?

    var cellSize: NSSize = .zero
    /// Receives everything the terminal tells or asks of its window. Returns
    /// whether the event was handled, which libghostty uses to decide whether
    /// a key binding consumed its key.
    var onEvent: ((TerminalEvent) -> Bool)?

    private var contentSize: NSSize = .zero
    private var focused = false
    /// What libghostty was last told; nil so the first call always reaches it.
    private var reportedVisibility: Bool?
    private var cursor = NSCursor.iBeam

    /// Non-nil only while inside keyDown, collecting text the IME commits.
    private var keyTextAccumulator: [String]?
    private var markedText = NSMutableAttributedString()

    /// See Ghostty's SurfaceView for the long story: command-modified keys go
    /// through performKeyEquivalent first, and doCommand needs to know whether
    /// to send them back through for encoding.
    private var lastPerformKeyEvent: TimeInterval?

    var backingScale: Double { Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) }

    static func from(userdata: UnsafeMutableRawPointer?) -> TerminalView? {
        guard let userdata else { return nil }
        return Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
    }

    static func from(surface: ghostty_surface_t?) -> TerminalView? {
        guard let surface else { return nil }
        return from(userdata: ghostty_surface_userdata(surface))
    }

    /// Returns nil if libghostty cannot create the surface; the reason is logged.
    /// A terminal split from `parent` takes its font size and live directory
    /// when window-inherit-font-size and window-inherit-working-directory are
    /// on; otherwise it starts in `options.workingDirectory`.
    init?(app: GhosttyApp, options: Options = Options(), splitFrom parent: TerminalView? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        // libghostty makes this view layer-hosting itself (it assigns the Metal
        // layer before setting wantsLayer), so we must not touch wantsLayer first.
        guard let surface = makeSurface(app: app, options: options, parent: parent?.surface) else { return nil }
        self.surface = surface
        reportColorScheme()
        updateTrackingAreas()
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    isolated deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    private func makeSurface(app: GhosttyApp, options: Options, parent: ghostty_surface_t?) -> ghostty_surface_t? {
        guard let ghosttyApp = app.app else {
            Logger.ghostty.error("cannot create a surface without a running libghostty app")
            return nil
        }
        // An inherited config carries the parent's live directory when
        // window-inherit-working-directory is on, and null otherwise. It is
        // allocated and libghostty exposes no way to free it; Ghostty's own
        // app leaks it the same way.
        var config =
            parent.map { ghostty_surface_inherited_config($0, GHOSTTY_SURFACE_CONTEXT_SPLIT) }
            ?? ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        if parent == nil {
            config.font_size = 0
            config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        }

        // libghostty copies every string during ghostty_surface_new.
        let surface = CBorrowScope.with { scope in
            if config.working_directory == nil, let workingDirectory = options.workingDirectory {
                config.working_directory = scope.copy(workingDirectory)
            }
            config.command = options.command.map { scope.copy($0) }
            config.initial_input = options.initialInput.map { scope.copy($0) }
            var environment = options.environment.map { key, value in
                ghostty_env_var_s(key: scope.copy(key), value: scope.copy(value))
            }
            return environment.withUnsafeMutableBufferPointer { buffer in
                config.env_vars = buffer.baseAddress
                config.env_var_count = buffer.count
                return ghostty_surface_new(ghosttyApp, &config)
            }
        }
        if surface == nil { Logger.ghostty.error("ghostty_surface_new failed") }
        return surface
    }

    // MARK: Talking to the window

    @discardableResult
    func send(_ event: TerminalEvent) -> Bool { onEvent?(event) ?? false }

    /// Whether closing would kill something the user may care about, such as
    /// a running command rather than an idle prompt.
    var needsConfirmClose: Bool {
        surface.map { ghostty_surface_needs_confirm_quit($0) } ?? false
    }

    /// Runs a Ghostty keybinding action such as `new_split:right`, exactly as
    /// if its key had been pressed, so menus and keys share one path.
    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }
    }

    /// Hidden terminals stop rendering until shown again. The workspace calls
    /// this for every pane on every change, so only changes reach libghostty.
    func setVisible(_ visible: Bool) {
        guard visible != reportedVisibility, let surface else { return }
        reportedVisibility = visible
        ghostty_surface_set_occlusion(surface, visible)
    }

    // MARK: Size and scale

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        contentSize = newSize
        pushSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeBackingProperties()
        if let surface, let screen = window?.screen,
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
        {
            ghostty_surface_set_display_id(surface, displayID)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reportColorScheme()
    }

    /// libghostty keeps a light or dark state per pane, and the app-wide one
    /// only seeds new panes, so each pane reports its own. Programs that asked
    /// (mode 2031) hear about the switch too. libghostty ignores repeats.
    private func reportColorScheme() {
        if let surface { ghostty_surface_set_color_scheme(surface, effectiveAppearance.ghosttyColorScheme) }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            // We handle scale ourselves, so stop the compositor from rescaling the layer.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        guard let surface, frame.width > 0, frame.height > 0 else { return }
        let backing = convertToBacking(frame)
        ghostty_surface_set_content_scale(surface, backing.width / frame.width, backing.height / frame.height)
        pushSize()
    }

    private func pushSize() {
        guard let surface, contentSize.width > 0, contentSize.height > 0 else { return }
        let scaled = convertToBacking(contentSize)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    // MARK: Focus

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            setFocused(true)
            send(.focused)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { setFocused(false) }
        return result
    }

    private func setFocused(_ value: Bool) {
        guard let surface, focused != value else { return }
        focused = value
        ghostty_surface_set_focus(surface, value)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Option-as-alt and friends: libghostty decides which mods take part in
        // character translation, and we rebuild the event to match.
        let translationModsGhostty = NSEvent.ModifierFlags(
            ghosttyMods: ghostty_surface_key_translation_mods(surface, event.modifierFlags.ghosttyMods))
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        // Reusing the original event when nothing changed matters: Korean input
        // breaks if AppKit gets a reconstructed event it did not create.
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent =
                NSEvent.keyEvent(
                    with: event.type,
                    location: event.locationInWindow,
                    modifierFlags: translationMods,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                    isARepeat: event.isARepeat,
                    keyCode: event.keyCode
                ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0
        let keyboardIdBefore: String? = markedTextBefore ? nil : Self.keyboardLayoutID
        lastPerformKeyEvent = nil

        interpretKeyEvents([translationEvent])

        // The key switched input source; an input method took it.
        if !markedTextBefore && keyboardIdBefore != Self.keyboardLayoutID { return }

        syncPreedit(clearIfNeeded: markedTextBefore)
        let composing = markedText.length > 0 || markedTextBefore

        if markedTextBefore, let list = keyTextAccumulator, !list.isEmpty {
            for text in list where !Self.shouldSuppressComposingControlInput(text, composing: composing) {
                _ = committedTextAction(action, text: text)
            }
            if shouldReplayCommittedPreeditKey(translationEvent) {
                _ = keyAction(action, event: event, translationEvent: translationEvent, composing: false)
            }
            return
        }

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list where !Self.shouldSuppressComposingControlInput(text, composing: composing) {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            if Self.shouldSuppressComposingControlInput(event.characters, composing: composing) { return }
            _ = keyAction(
                action, event: event, translationEvent: translationEvent,
                text: translationEvent.ghosttyCharacters, composing: composing)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused, let surface else { return false }

        // Ghostty keybindings (cmd+c, cmd+v, cmd+k, ...) take priority.
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding = (event.characters ?? "").withCString { ptr in
            keyEvent.text = ptr
            var flags = ghostty_binding_flags_e(0)
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
        if isBinding {
            keyDown(with: event)
            return true
        }

        let equivalent: String
        switch event.charactersIgnoringModifiers {
        case "\r":
            // Pass ctrl+return through instead of AppKit's context menu shortcut.
            guard event.modifierFlags.contains(.control) else { return false }
            equivalent = "\r"

        case "/":
            // ctrl+/ beeps on macOS; send it as ctrl+_ like other terminals.
            guard event.modifierFlags.contains(.control),
                event.modifierFlags.isDisjoint(with: [.shift, .command, .option])
            else { return false }
            equivalent = "_"

        default:
            if event.timestamp == 0 { return false }
            if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
                lastPerformKeyEvent = nil
                return false
            }
            if let last = lastPerformKeyEvent {
                lastPerformKeyEvent = nil
                if last == event.timestamp {
                    equivalent = event.characters ?? ""
                    break
                }
            }
            lastPerformKeyEvent = event.timestamp
            return false
        }

        guard
            let finalEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: equivalent,
                charactersIgnoringModifiers: equivalent,
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            )
        else { return false }
        keyDown(with: finalEvent)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        if hasMarkedText() { return }

        let mods = event.modifierFlags.ghosttyMods
        var action = GHOSTTY_ACTION_RELEASE
        if mods.rawValue & mod != 0 {
            // A press only counts if the side that changed is the one held down.
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default: sidePressed = true
            }
            if sidePressed { action = GHOSTTY_ACTION_PRESS }
        }
        _ = keyAction(action, event: event)
    }

    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }
        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing
        if let text = Self.keyText(text) {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    private func committedTextAction(_ action: ghostty_input_action_e, text: String) -> Bool {
        guard let surface else { return false }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        return text.withCString { ptr in
            keyEvent.text = ptr
            return ghostty_surface_key(surface, keyEvent)
        }
    }

    private func shouldReplayCommittedPreeditKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_DownArrow, kVK_RightArrow, kVK_UpArrow:
            return true
        case kVK_LeftArrow:
            // Korean IMEs already leave the caret in place after a plain left arrow.
            return !event.modifierFlags.isDisjoint(with: [.shift, .control, .option, .command])
        default:
            return false
        }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ghostty_surface_preedit(surface, $0, UInt(len - 1)) }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    /// Empty strings and leading control characters are left for libghostty to
    /// encode, so protocols like Kitty keyboard still see the physical key.
    private static func keyText(_ text: String?) -> String? {
        guard let text, let scalar = text.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F else {
            return nil
        }
        return text
    }

    /// A lone C0 control character during composition belongs to the IME.
    static func shouldSuppressComposingControlInput(_ text: String?, composing: Bool) -> Bool {
        guard composing, let text else { return false }
        let scalars = text.unicodeScalars
        guard let scalar = scalars.first, scalars.count == 1 else { return false }
        return scalar.value < 0x20
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: frame,
                options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
                owner: self,
                userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, event.modifierFlags.ghosttyMods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, event.modifierFlags.ghosttyMods)
        ghostty_surface_mouse_pressure(surface, 0, 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface,
            ghostty_surface_mouse_button(
                surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event.modifierFlags.ghosttyMods
            )
        else { return super.rightMouseDown(with: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface,
            ghostty_surface_mouse_button(
                surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event.modifierFlags.ghosttyMods
            )
        else { return super.rightMouseUp(with: event) }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface, GHOSTTY_MOUSE_PRESS, Self.mouseButton(event.buttonNumber), event.modifierFlags.ghosttyMods)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(
            surface, GHOSTTY_MOUSE_RELEASE, Self.mouseButton(event.buttonNumber), event.modifierFlags.ghosttyMods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        // AppKit's origin is bottom-left; libghostty's is top-left.
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, event.modifierFlags.ghosttyMods)
    }

    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        // While dragging we keep getting events outside the view, so only
        // report "left the viewport" when no button is held.
        guard let surface, NSEvent.pressedMouseButtons == 0 else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, event.modifierFlags.ghosttyMods)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            // Upstream's 2x feels right on a trackpad.
            x *= 2
            y *= 2
        }
        // Bit 0 is precision, bits 1-3 the momentum phase.
        var mods: Int32 = precision ? 1 : 0
        mods |= Int32(Self.momentum(event.momentumPhase).rawValue) << 1
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    override func pressureChange(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))
    }

    func setCursorShape(_ shape: ghostty_action_mouse_shape_e) {
        let cursor: NSCursor
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT: cursor = .iBeam
        case GHOSTTY_MOUSE_SHAPE_POINTER: cursor = .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: cursor = .crosshair
        case GHOSTTY_MOUSE_SHAPE_GRAB: cursor = .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: cursor = .closedHand
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: cursor = .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE, GHOSTTY_MOUSE_SHAPE_EW_RESIZE: cursor = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE, GHOSTTY_MOUSE_SHAPE_NS_RESIZE: cursor = .resizeUpDown
        default: cursor = .arrow
        }
        // A cursor rect, so views laid over the terminal (split dividers) keep
        // their own cursor. Rects only apply once the mouse moves, so a shape
        // that changes under a still mouse (Cmd over a link, OSC 22) is also
        // set now, when nothing else is under the mouse.
        self.cursor = cursor
        window?.invalidateCursorRects(for: self)
        if let window, let content = window.contentView,
            content.hitTest(window.mouseLocationOutsideOfEventStream) === self
        {
            cursor.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let surface else { return false }
        let pasteboard = sender.draggingPasteboard
        guard let data = pasteboard.data(forMIMEType: "text/plain"),
            let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return false }
        // Paste, not type: paste protection asks before text with a newline runs.
        text.withCString { ghostty_surface_paste_text(surface, $0, UInt(text.utf8.count)) }
        return true
    }

    // MARK: Helpers

    private static func mouseButton(_ number: Int) -> ghostty_input_mouse_button_e {
        switch number {
        case 2: return GHOSTTY_MOUSE_MIDDLE
        case 3: return GHOSTTY_MOUSE_FOUR
        case 4: return GHOSTTY_MOUSE_FIVE
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    private static func momentum(_ phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
        switch phase {
        case .began: return GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary: return GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed: return GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended: return GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled: return GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin: return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default: return GHOSTTY_MOUSE_MOMENTUM_NONE
        }
    }

    private static var keyboardLayoutID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return unsafeBitCast(pointer, to: CFString.self) as String
    }
}

// MARK: - NSTextInputClient

extension TerminalView: NSTextInputClient {
    func hasMarkedText() -> Bool { markedText.length > 0 }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange()
    }

    func selectedRange() -> NSRange {
        guard let surface else { return NSRange() }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let value as NSAttributedString: markedText = NSMutableAttributedString(attributedString: value)
        case let value as String: markedText = NSMutableAttributedString(string: value)
        default: return
        }
        // Outside keyDown (e.g. switching layouts mid-composition) update right away.
        if keyTextAccumulator == nil { syncPreedit() }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let surface, range.length > 0 else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSAttributedString(string: String(cString: text.text))
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return NSRect(origin: frame.origin, size: .zero) }
        var x: Double = 0
        var y: Double = 0
        var width = Double(cellSize.width)
        var height = Double(cellSize.height)
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        if range.length == 0, width > 0 {
            // Dictation's mic indicator wants a zero-width caret rect.
            width = 0
            x += Double(cellSize.width) * Double(range.location + range.length)
        }
        let viewRect = NSRect(x: x, y: frame.height - y, width: width, height: max(height, Double(cellSize.height)))
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        let chars: String
        switch string {
        case let value as NSAttributedString: chars = value.string
        case let value as String: chars = value
        default: return
        }

        unmarkText()

        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }
        // Committed text (IME, dictation) is typed input, never a paste.
        if !chars.isEmpty { _ = committedTextAction(GHOSTTY_ACTION_PRESS, text: chars) }
    }

    override func doCommand(by selector: Selector) {
        // Send command-modified keys we didn't bind back through for encoding.
        if let last = lastPerformKeyEvent, let current = NSApp.currentEvent, last == current.timestamp {
            NSApp.sendEvent(current)
        }
    }
}
