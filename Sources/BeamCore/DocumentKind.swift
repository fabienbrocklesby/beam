import Foundation

/// How Beam shows a file, or that it leaves the file to another app.
public enum DocumentKind: Equatable, Sendable {
    case pdf
    case markdown
    /// Plain or rich text, read only.
    case text
    /// Anything `NSImage` draws, SVG included.
    case image
    /// Audio and video, which Quick Look plays.
    case quickLook
    /// Not Beam's to show: it opens in its own app.
    case external

    /// Extensions that mean Markdown. macOS knows only the first two as its
    /// Markdown type.
    private static let markdownExtensions: Set = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// - Parameters:
    ///   - path: The file, for its extension.
    ///   - types: The identifiers of the file's type and of every type that
    ///     conforms to, as `UTType` lists them.
    ///   - chosen: Whether the user picked Beam for this file, as from
    ///     Finder. A file a click named goes to the user's editor when it is
    ///     code or config; a chosen one shows as text.
    public init(path: String, types: Set<String>, chosen: Bool = false) {
        let fallback: Self = chosen ? .text : .external
        let isMarkdown =
            types.contains("net.daringfireball.markdown")
            || Self.markdownExtensions.contains(URL(filePath: path).pathExtension.lowercased())
        if isMarkdown {
            self = .markdown
        } else if types.contains("com.adobe.pdf") {
            self = .pdf
        } else if types.contains("public.image") {
            // Before code: SVG is an image and XML at once.
            self = .image
        } else if FileMention.isTypeScript(path) {
            self = fallback
        } else if types.contains("public.audiovisual-content") {
            self = .quickLook
        } else if types.contains("public.source-code") || types.contains("public.script") {
            self = fallback
        } else if types.contains("public.plain-text") || types.contains("public.rtf") {
            self = .text
        } else {
            // Config formats are text but not plain text, and Office and
            // iWork files are only data.
            self = fallback
        }
    }
}
