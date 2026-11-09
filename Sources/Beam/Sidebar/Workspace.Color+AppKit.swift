import AppKit
import BeamCore

extension Workspace.Color {
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }

    var title: String { rawValue.capitalized }

    /// A filled dot in this colour, for rows and menus.
    var dot: NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [nsColor])
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
    }
}
