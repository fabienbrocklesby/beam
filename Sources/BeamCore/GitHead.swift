import Foundation

/// What a folder's git repository has checked out, read the way git reads
/// it: from the HEAD file of the nearest enclosing repository.
public enum GitHead {
    /// The HEAD file of the repository containing `folder`, or nil if there
    /// is none. `.git` is usually the git directory itself; in a linked
    /// worktree or a submodule it is a file naming that directory.
    public static func file(containing folder: String) -> String? {
        var directory = (folder as NSString).standardizingPath
        while true {
            let dotGit = (directory as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                guard !isDirectory.boolValue else { return (dotGit as NSString).appendingPathComponent("HEAD") }
                return gitDirectory(named: dotGit, from: directory).map {
                    ($0 as NSString).appendingPathComponent("HEAD")
                }
            }
            let parent = (directory as NSString).deletingLastPathComponent
            guard parent != directory else { return nil }
            directory = parent
        }
    }

    /// The name of what the HEAD file at `path` points to, or nil if it
    /// cannot be read.
    public static func name(ofFile path: String) -> String? {
        (try? String(contentsOfFile: path, encoding: .utf8)).flatMap(name(fromContents:))
    }

    /// The branch HEAD points to, or its commit abbreviated as git does when
    /// HEAD is detached. nil for anything that is neither.
    public static func name(fromContents contents: String) -> String? {
        let head = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref:") {
            let ref = head.dropFirst("ref:".count).trimmingCharacters(in: .whitespaces)
            guard !ref.isEmpty else { return nil }
            let branches = "refs/heads/"
            return ref.hasPrefix(branches) ? String(ref.dropFirst(branches.count)) : ref
        }
        guard head.count >= 40, head.allSatisfy(\.isHexDigit) else { return nil }
        return String(head.prefix(7))
    }

    /// The directory a `.git` file's `gitdir:` line names, resolved against
    /// `folder` when relative.
    private static func gitDirectory(named file: String, from folder: String) -> String? {
        let prefix = "gitdir:"
        guard let contents = try? String(contentsOfFile: file, encoding: .utf8),
            let line = contents.split(whereSeparator: \.isNewline).first,
            line.hasPrefix(prefix)
        else { return nil }
        let path = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let absolute = path.hasPrefix("/") ? path : (folder as NSString).appendingPathComponent(path)
        return (absolute as NSString).standardizingPath
    }
}
