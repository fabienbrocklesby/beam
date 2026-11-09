import BeamCore
import GhosttyVt

/// A session's screen, kept by libghostty-vt from everything the session
/// prints, so a pane that attaches later can be given it back. The only code
/// in beamd that calls `ghostty_*`.
final class VirtualTerminal {
    enum Failure: Error {
        case create
    }

    /// Ghostty's default `scrollback-limit`, so a reattached pane keeps as
    /// much history as one that never detached.
    private static let scrollbackBytes = 10_000_000
    /// Room for the escape sequence a read can end inside of, so the replay
    /// can finish it. Far above any real one but a kitty image, which beamd
    /// does not keep.
    private static let continuationBytes = 1 << 20

    private let terminal: GhosttyTerminal
    /// The terminal's answers to queries (device attributes, cursor
    /// position, colours), meant for the program that asked.
    var onAnswer: (([UInt8]) -> Void)?

    init(size: WindowSize) throws {
        var terminal: GhosttyTerminal?
        guard ghostty_terminal_new(nil, &terminal, max(size.columns, 1), max(size.rows, 1)) == GHOSTTY_SUCCESS,
            let terminal
        else { throw Failure.create }
        self.terminal = terminal
        var scrollback = Self.scrollbackBytes
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, &scrollback)
        var continuation = Self.continuationBytes
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES, &continuation)
        let answer: GhosttyTerminalWritePtyFn = { _, owner, bytes, count in
            guard let owner, let bytes else { return }
            // libghostty-vt calls this from inside `write`, on the main queue.
            MainActor.assumeIsolated {
                let terminal = Unmanaged<VirtualTerminal>.fromOpaque(owner).takeUnretainedValue()
                terminal.onAnswer?(Array(UnsafeBufferPointer(start: bytes, count: count)))
            }
        }
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_USERDATA, Unmanaged.passUnretained(self).toOpaque())
        _ = ghostty_terminal_set(
            terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(answer, to: UnsafeRawPointer.self))
    }

    isolated deinit {
        ghostty_terminal_free(terminal)
    }

    func write(_ bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.baseAddress else { return }
        ghostty_terminal_vt_write(terminal, base.assumingMemoryBound(to: UInt8.self), bytes.count)
    }

    func resize(_ size: WindowSize) {
        let columns = max(size.columns, 1)
        let rows = max(size.rows, 1)
        _ = ghostty_terminal_resize(
            terminal, columns, rows, UInt32(size.width / columns), UInt32(size.height / rows))
    }

    /// Everything a fresh terminal needs to show what this one shows, and to
    /// carry on from where its input stopped (see `docs/sessions.md`).
    func replay() -> [UInt8] {
        ReplaySequence.reset + formatted() + ReplaySequence.palette(palette(.current), defaults: palette(.defaults))
            + ReplaySequence.title(title) + ReplaySequence.inputStart(atPrompt: isCursorAtPrompt) + continuation()
    }

    /// Screen and scrollback with their styles, the modes that differ from
    /// the defaults, and the cursor, as VT sequences.
    private func formatted() -> [UInt8] {
        var options = GhosttyFormatterTerminalOptions()
        options.size = MemoryLayout<GhosttyFormatterTerminalOptions>.size
        options.emit = GHOSTTY_FORMATTER_FORMAT_VT
        options.extra.size = MemoryLayout<GhosttyFormatterTerminalExtra>.size
        options.extra.modes = true
        options.extra.scrolling_region = true
        options.extra.tabstops = true
        options.extra.pwd = true
        options.extra.keyboard = true
        options.extra.screen.size = MemoryLayout<GhosttyFormatterScreenExtra>.size
        options.extra.screen.cursor = true
        options.extra.screen.style = true
        options.extra.screen.hyperlink = true
        options.extra.screen.protection = true
        options.extra.screen.kitty_keyboard = true
        options.extra.screen.charsets = true
        var formatter: GhosttyFormatter?
        guard ghostty_formatter_terminal_new(nil, &formatter, terminal, options) == GHOSTTY_SUCCESS else { return [] }
        defer { ghostty_formatter_free(formatter) }
        var bytes: UnsafeMutablePointer<UInt8>?
        var count = 0
        guard ghostty_formatter_format_alloc(formatter, nil, &bytes, &count) == GHOSTTY_SUCCESS, let bytes else {
            return []
        }
        defer { ghostty_free(nil, bytes, count) }
        return Array(UnsafeBufferPointer(start: bytes, count: count))
    }

    /// The unfinished escape sequence the last read ended inside of, if any.
    private func continuation() -> [UInt8] {
        var bytes: UnsafeMutablePointer<UInt8>?
        var count = 0
        guard ghostty_terminal_continuation_alloc(terminal, nil, &bytes, &count) == GHOSTTY_SUCCESS, let bytes else {
            return []
        }
        defer { ghostty_free(nil, bytes, count) }
        return Array(UnsafeBufferPointer(start: bytes, count: count))
    }

    /// Whether the shell's prompt marks put the cursor at its prompt, which
    /// is what Ghostty checks before closing a pane without asking.
    var isCursorAtPrompt: Bool {
        var atPrompt = false
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_CURSOR_AT_PROMPT, &atPrompt) == GHOSTTY_SUCCESS
        else { return false }
        return atPrompt
    }

    private var title: String {
        var title = GhosttyString()
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TITLE, &title) == GHOSTTY_SUCCESS,
            let bytes = title.ptr
        else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: title.len), as: UTF8.self)
    }

    private enum Palette {
        case current, defaults
    }

    private func palette(_ which: Palette) -> [ReplaySequence.Color] {
        var colors = [GhosttyColorRgb](repeating: GhosttyColorRgb(), count: 256)
        let key = which == .current ? GHOSTTY_TERMINAL_DATA_COLOR_PALETTE : GHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT
        guard ghostty_terminal_get(terminal, key, &colors) == GHOSTTY_SUCCESS else { return [] }
        return colors.map { ReplaySequence.Color(red: $0.r, green: $0.g, blue: $0.b) }
    }
}
