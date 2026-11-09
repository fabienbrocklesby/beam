import AppKit
import GhosttyKit

// Ported from Ghostty's macOS app (MIT, see NOTICE).
extension NSEvent {
    /// Text and composing are left unset: their lifetimes belong to the caller.
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        // Control and command never contribute to text; assume everything else did.
        keyEvent.mods = modifierFlags.ghosttyMods
        keyEvent.consumed_mods = (translationMods ?? modifierFlags).subtracting([.control, .command]).ghosttyMods
        keyEvent.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp,
            let scalar = characters(byApplyingModifiers: [])?.unicodeScalars.first
        {
            keyEvent.unshifted_codepoint = scalar.value
        }
        return keyEvent
    }

    /// libghostty encodes control characters itself, and function keys arrive
    /// as private-use codepoints we must not forward.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        }
        return characters
    }
}

extension NSEvent.ModifierFlags {
    init(ghosttyMods mods: ghostty_input_mods_e) {
        self = []
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { insert(.command) }
    }

    var ghosttyMods: ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        if rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if rawValue & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(mods)
    }
}
