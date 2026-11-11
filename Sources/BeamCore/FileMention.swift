import Foundation

/// What a link on screen or a word in an agent's message names: a web
/// address, or a file whose path may be partial. `FileResolver` finds the
/// file on disk.
public enum FileMention: Equatable, Sendable {
    case web(URL)
    /// Absolute, or relative to a folder the text does not say, with `~`
    /// expanded and any `:line:column` dropped.
    case file(String)

    /// The schemes Ghostty's link regex matches (`vendor/ghostty/src/config/url.zig`),
    /// other than `file:`, which names a path.
    private static let webSchemes = [
        "http://", "https://", "mailto:", "ftp://", "ssh:", "git://", "tel:", "magnet:", "ipfs://", "ipns://",
        "gemini://", "gopher://", "news:",
    ]

    /// Nil when `text` names nothing.
    public init?(_ text: String, home: String) {
        let lowercased = text.lowercased()
        if let scheme = Self.webSchemes.first(where: lowercased.hasPrefix) {
            guard text.count > scheme.count, let url = URL(string: text) else { return nil }
            self = .web(url)
            return
        }

        var path = Substring(text)
        if lowercased.hasPrefix("file:") {
            path = Substring(URL(string: text)?.path(percentEncoded: false) ?? String(text.dropFirst(5)))
        }
        path = Self.droppingLocation(path)
        if path == "~" || path.hasPrefix("~/") {
            path = home + path.dropFirst()
        } else if path.hasPrefix("$HOME/") {
            path = home + path.dropFirst(5)
        } else if path.hasPrefix("$PWD/") {
            path = path.dropFirst(5)
        }
        guard !path.isEmpty else { return nil }
        self = .file(String(path))
    }

    /// `path` without a trailing `:line`, `:line:column` or a lone colon.
    private static func droppingLocation(_ path: Substring) -> Substring {
        var path = path
        for _ in 0..<2 {
            if path.last == ":" { path = path.dropLast() }
            guard let colon = path.lastIndex(of: ":") else { break }
            let number = path[path.index(after: colon)...]
            guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { break }
            path = path[..<colon]
        }
        return path
    }
}
