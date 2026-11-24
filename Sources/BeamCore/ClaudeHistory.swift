import Foundation

/// The conversations Claude Code keeps: a JSONL file per session, named for
/// its ID, in a folder per project under `~/.claude/projects`.
///
/// Nothing documents the format, so only what a list needs is read, and a
/// record of any other shape is skipped: the folder a session ran in comes
/// from its first records, and its title from its last, where Claude Code
/// writes it again as the session grows. A session runs to tens of
/// megabytes, so only its two ends are read.
public struct ClaudeHistory: Sendable {
    /// The fields Beam reads, each on a record of its own kind.
    private struct Record: Decodable {
        var cwd: String?
        var aiTitle: String?
        var customTitle: String?
        var lastPrompt: String?
    }

    /// How much of each end of a session is read. The folder was within the
    /// first 12KB of each of 393 sessions, and a title within the last 64KB
    /// of every one that had one.
    private static let chunk = 64 * 1024
    /// Where Claude Code cuts a project folder's name, before a hash.
    private static let nameLimit = 200
    /// Longest title a conversation carries: more than a row shows.
    private static let titleLimit = 100

    public let projects: URL

    public init(projects: URL) {
        self.projects = projects
    }

    /// The history of the user whose home folder is `home`.
    public init(home: String) {
        projects = URL(filePath: home).appending(path: ".claude/projects")
    }

    /// The conversations that ran in `folder` or in a folder inside it,
    /// newest first. Reads files, so callers keep it off the main thread.
    public func conversations(in folder: String) -> [Conversation] {
        let manager = FileManager.default
        let folder = Self.resolved(folder)
        let prefix = Self.projectPrefix(for: folder)
        let root = (folder as NSString).pathComponents
        var found: [Conversation] = []
        for name in (try? manager.contentsOfDirectory(atPath: projects.path)) ?? [] where name.hasPrefix(prefix) {
            let sessions = try? manager.contentsOfDirectory(
                at: projects.appending(path: name), includingPropertiesForKeys: [.contentModificationDateKey])
            for file in sessions ?? [] where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modified = values?.contentModificationDate, let (head, tail) = Self.ends(of: file),
                    let conversation = Self.conversation(
                        session: file.deletingPathExtension().lastPathComponent, head: head, tail: tail,
                        modified: modified),
                    // Paths that differ share a project name, so the session
                    // says whether it ran here.
                    (conversation.folder as NSString).pathComponents.starts(with: root)
                else { continue }
                found.append(conversation)
            }
        }
        return found.sorted { $0.modified > $1.modified }
    }

    /// Where `path` really is, which is what Claude Code goes by:
    /// `/private/tmp` for `/tmp`, and a link's target for a link.
    /// Foundation's own resolving takes `/private` off again.
    private static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    /// How the name of the folder Claude Code keeps `path`'s sessions in
    /// starts: the path with every UTF-16 unit but an ASCII letter or digit
    /// turned to `-`, up to where a long name is cut. A folder inside
    /// `path` starts the same way, and so can one beside it.
    public static func projectPrefix(for path: String) -> String {
        let kept = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf16)
        let dash = UInt16(UInt8(ascii: "-"))
        return String(decoding: path.utf16.prefix(nameLimit).map { kept.contains($0) ? $0 : dash }, as: UTF16.self)
    }

    /// The conversation in the session whose file starts with `head` and
    /// ends with `tail`, or nil when it names no folder or nothing was said
    /// in it. It goes by the name the user gave it, else the one Claude Code
    /// generated, else its last prompt.
    public static func conversation(session: String, head: Data, tail: Data, modified: Date) -> Conversation? {
        guard let folder = records(in: head).lazy.compactMap(\.cwd).first else { return nil }
        let last = records(in: tail)
        let named = last.last { $0.customTitle != nil }?.customTitle ?? last.last { $0.aiTitle != nil }?.aiTitle
        let prompt = last.last { $0.lastPrompt != nil }?.lastPrompt
        // Claude Code wraps what was pasted or attached in tags.
        guard let title = named.flatMap(line) ?? prompt.flatMap({ line($0.replacing(/<[^<>]*>/, with: " ")) }) else {
            return nil
        }
        return Conversation(agent: .claude, session: session, folder: folder, title: title, modified: modified)
    }

    /// The records in `data`, one to a line. A line that is no record, as
    /// one cut short at either end of a chunk is, counts for nothing.
    private static func records(in data: Data) -> [Record] {
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Record.self, from: $0) }
    }

    /// The first and last `chunk` bytes of `file`, which overlap in a short
    /// one. Nil when it is empty or cannot be read.
    private static func ends(of file: URL) -> (head: Data, tail: Data)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: chunk), !head.isEmpty, let size = try? handle.seekToEnd() else {
            return nil
        }
        guard size > UInt64(chunk) else { return (head, head) }
        guard (try? handle.seek(toOffset: size - UInt64(chunk))) != nil, let tail = try? handle.readToEnd() else {
            return nil
        }
        return (head, tail)
    }

    /// The first line of `text` with any text, cut to `titleLimit`.
    private static func line(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count <= titleLimit ? line : line.prefix(titleLimit - 1) + "…"
    }
}
