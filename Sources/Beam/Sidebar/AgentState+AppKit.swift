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

    /// The symbol in the state's colour.
    var image: NSImage? {
        let color: NSColor =
            switch self {
            case .working: .secondaryLabelColor
            case .waiting: .systemOrange
            case .done: .systemGreen
            }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
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
