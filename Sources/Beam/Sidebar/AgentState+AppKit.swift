import AppKit
import BeamCore

extension AgentState {
    /// What VoiceOver and tooltips call the state.
    var title: String {
        switch self {
        case .working: "Agent working"
        case .waiting: "Agent needs you"
        case .done: "Agent done"
        }
    }

    /// A symbol rather than a coloured dot, so it reads apart from the
    /// workspace's colour tag and without colour at all.
    var symbolName: String {
        switch self {
        case .working: "ellipsis.circle"
        case .waiting: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    /// The symbol in the state's colour. A filled symbol's glyph is its first
    /// layer and needs a colour of its own: one palette colour paints every
    /// layer, leaving a plain dot.
    var image: NSImage? {
        let colors: [NSColor] =
            switch self {
            case .working: [.secondaryLabelColor]
            case .waiting: [.white, .systemOrange]
            case .done: [.white, .systemGreen]
            }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: colors))
    }

    /// What the agent said, or the state's title when it said nothing.
    var detail: String {
        switch self {
        case .working: title
        case .waiting(let message): message
        case .done(let message): message ?? title
        }
    }
}
