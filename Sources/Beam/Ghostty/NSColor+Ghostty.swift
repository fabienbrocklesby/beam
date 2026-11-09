import AppKit
import GhosttyKit

// Colours as the user's Ghostty config gives them.
extension NSColor {
    convenience init(_ color: ghostty_config_color_s) {
        self.init(
            srgbRed: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255, alpha: 1)
    }
}
