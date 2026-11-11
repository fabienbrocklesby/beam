import Foundation

/// Finds the file a path names when the text it came from left it partial.
/// Agents name a file they wrote by its name alone, often in a scratchpad
/// far from where they work, and a link on screen is relative to a folder
/// the screen does not show.
///
/// Every candidate is checked on disk, so a path that names nothing is
/// dropped rather than shown. The checks block: call this off the main
/// thread.
public struct FileResolver: Sendable {
    private let exists: @Sendable (String) -> Bool

    /// `exists` says whether something is at an absolute path.
    public init(exists: @escaping @Sendable (String) -> Bool) {
        self.exists = exists
    }

    /// Checks the file system.
    public static let disk = FileResolver { FileManager.default.fileExists(atPath: $0) }

    /// The absolute path of what `path` names, or nil when nothing there
    /// exists. A relative path is, in order: the end of a file in `touched`,
    /// the absolute paths of what the agent's tools named this turn; under
    /// `directory`, where the text was written; or beside a file in
    /// `touched`.
    public func path(for path: String, directory: String?, touched: [String]) -> String? {
        if path.hasPrefix("/") { return existing(path) }

        let suffix = "/" + path
        let candidates =
            touched.filter { $0.hasSuffix(suffix) }
            + (directory.map { [$0 + suffix] } ?? [])
            + Self.folders(of: touched).map { $0 + suffix }
        return candidates.lazy.compactMap(existing).first
    }

    /// `path` without `.` and `..`, if it exists.
    private func existing(_ path: String) -> String? {
        let standardized = URL(filePath: path, directoryHint: .notDirectory).standardized.path(percentEncoded: false)
        return exists(standardized) ? standardized : nil
    }

    /// The folders `files` are in, each once, in order.
    private static func folders(of files: [String]) -> [String] {
        var seen = Set<String>()
        return files.map { ($0 as NSString).deletingLastPathComponent }.filter { seen.insert($0).inserted }
    }
}
