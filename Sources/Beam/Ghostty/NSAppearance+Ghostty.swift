import AppKit
import GhosttyKit

extension NSAppearance {
    /// Picks the light or dark half of a `theme = light:...,dark:...` config.
    /// High contrast appearances count as their light or dark base.
    var ghosttyColorScheme: ghostty_color_scheme_e {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }
}
