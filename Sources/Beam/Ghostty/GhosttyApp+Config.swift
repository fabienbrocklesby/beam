import AppKit
import GhosttyKit

// What the rest of the app reads from the user's Ghostty config, as last
// applied. Callers read it again after `onConfigChange`.
extension GhosttyApp {
    /// How panes look next to each other, from the `unfocused-split-*` and
    /// `split-divider-color` options.
    struct SplitStyle {
        /// The terminal's background, which pane chrome shares.
        var background: NSColor
        /// A pane header's strip: the background a shade toward the text.
        var headerBackground: NSColor
        /// How strongly `unfocusedFill` covers an unfocused pane, from 0 to 1.
        var unfocusedFillOpacity: Double
        var unfocusedFill: NSColor
        var dividerColor: NSColor
    }

    /// A menu item's key equivalent.
    struct KeyEquivalent {
        var key: String
        var modifiers: NSEvent.ModifierFlags
    }

    /// Whether quitting would kill a running command in any terminal.
    var needsConfirmQuit: Bool {
        app.map { ghostty_app_needs_confirm_quit($0) } ?? false
    }

    var splitStyle: SplitStyle {
        // The option is how opaque an unfocused pane stays; the fill covers the rest.
        var opacity = 0.7
        _ = value(of: "unfocused-split-opacity", into: &opacity)

        var background = ghostty_config_color_s()
        _ = value(of: "background", into: &background)
        let base = NSColor(background)
        let isLight = base.brightnessComponent > 0.5

        // Ghostty fills with the background, which on a light one only fades
        // the text. A grey there also tints the pane, so the focused pane is
        // the one left white.
        var fill = ghostty_config_color_s()
        let fillColor =
            value(of: "unfocused-split-fill", into: &fill)
            ? NSColor(fill) : isLight ? base.blended(withFraction: 0.12, of: .black) ?? base : base

        // Without an explicit colour, darken the background the way Ghostty
        // does, a little more on a light one, where its shade vanishes.
        var divider = ghostty_config_color_s()
        let dividerColor: NSColor
        if value(of: "split-divider-color", into: &divider) {
            dividerColor = NSColor(divider)
        } else {
            dividerColor = base.blended(withFraction: isLight ? 0.14 : 0.4, of: .black) ?? base
        }

        return SplitStyle(
            background: base,
            headerBackground: base.blended(withFraction: isLight ? 0.04 : 0.05, of: isLight ? .black : .white) ?? base,
            unfocusedFillOpacity: 1 - opacity, unfocusedFill: fillColor, dividerColor: dividerColor)
    }

    /// The key the user's config binds to a keybinding `action` such as
    /// `new_split:right`, or nil when it is unbound or a menu cannot show it.
    func keyEquivalent(for action: String) -> KeyEquivalent? {
        let trigger = action.withCString { ghostty_config_trigger(config, $0, UInt(action.utf8.count)) }
        let modifiers = NSEvent.ModifierFlags(ghosttyMods: trigger.mods)
        switch trigger.tag {
        case GHOSTTY_TRIGGER_UNICODE:
            guard let scalar = Unicode.Scalar(trigger.key.unicode) else { return nil }
            return KeyEquivalent(key: String(Character(scalar)).lowercased(), modifiers: modifiers)
        case GHOSTTY_TRIGGER_PHYSICAL:
            guard let key = Self.menuKeys[trigger.key.physical.rawValue] else { return nil }
            return KeyEquivalent(key: key, modifiers: modifiers)
        default:
            return nil
        }
    }

    /// Physical keys whose menu key equivalent does not depend on the keyboard
    /// layout. Letters and punctuation are bound as unicode by default.
    private static let menuKeys: [UInt32: String] = {
        var keys = [
            GHOSTTY_KEY_ENTER.rawValue: "\r",
            GHOSTTY_KEY_ARROW_UP.rawValue: functionKey(NSUpArrowFunctionKey),
            GHOSTTY_KEY_ARROW_DOWN.rawValue: functionKey(NSDownArrowFunctionKey),
            GHOSTTY_KEY_ARROW_LEFT.rawValue: functionKey(NSLeftArrowFunctionKey),
            GHOSTTY_KEY_ARROW_RIGHT.rawValue: functionKey(NSRightArrowFunctionKey),
        ]
        // The digit keys are contiguous in ghostty_input_key_e.
        for digit in 0...9 {
            keys[GHOSTTY_KEY_DIGIT_0.rawValue + UInt32(digit)] = String(digit)
        }
        return keys
    }()

    private static func functionKey(_ key: Int) -> String {
        String(Character(Unicode.Scalar(UInt16(key)) ?? " "))
    }

    private func value<Value>(of key: String, into value: inout Value) -> Bool {
        withUnsafeMutablePointer(to: &value) { pointer in
            key.withCString { ghostty_config_get(config, pointer, $0, UInt(key.utf8.count)) }
        }
    }
}
