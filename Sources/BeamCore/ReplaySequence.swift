/// The escape sequences beamd wraps around libghostty-vt's formatted screen
/// when a pane attaches, for the state the formatter does not write itself.
public enum ReplaySequence {
    public struct Color: Equatable, Sendable {
        public var red: UInt8
        public var green: UInt8
        public var blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Full reset (RIS) then erase scrollback: the pane starts from nothing,
    /// whatever it showed before beam-attach connected.
    public static let reset: [UInt8] = Array("\u{1b}c\u{1b}[3J".utf8)

    /// OSC 4 for each entry of `current` that differs from `defaults`. The
    /// formatter can only write all 256, which would replace the pane's theme
    /// with libghostty-vt's built-in palette.
    public static func palette(_ current: [Color], defaults: [Color]) -> [UInt8] {
        zip(current, defaults).enumerated().flatMap { index, pair -> [UInt8] in
            let (color, original) = pair
            guard color != original else { return [] }
            return Array("\u{1b}]4;\(index);rgb:\(hex(color.red))/\(hex(color.green))/\(hex(color.blue))\u{1b}\\".utf8)
        }
    }

    /// OSC 2 setting the title, which the formatter does not write. Control
    /// characters would end the sequence early, so they are dropped.
    public static func title(_ title: String) -> [UInt8] {
        guard !title.isEmpty else { return [] }
        let printable = title.unicodeScalars.filter { $0.properties.generalCategory != .control }
        return Array("\u{1b}]2;\(String(String.UnicodeScalarView(printable)))\u{1b}\\".utf8)
    }

    /// OSC 133;B (input start) when the session's cursor is at its prompt.
    /// The formatter writes no prompt marks, and without one the pane takes
    /// an idle shell for a running command and asks before closing it. The
    /// mark sets only the cursor's state, so the screen stays as replayed.
    public static func inputStart(atPrompt: Bool) -> [UInt8] {
        atPrompt ? Array("\u{1b}]133;B\u{1b}\\".utf8) : []
    }

    private static func hex(_ value: UInt8) -> String {
        let digits = String(value, radix: 16)
        return digits.count == 1 ? "0" + digits : digits
    }
}
