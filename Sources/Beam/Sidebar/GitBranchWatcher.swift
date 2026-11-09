import BeamCore
import Foundation

/// Follows the branch checked out in a folder, for the sidebar. Finding the
/// repository and reading HEAD happen on a background queue; the branch
/// reaches `onChange` on the main actor once it is known and whenever it
/// changes. A folder that only becomes a repository later shows its branch
/// from the next launch.
///
/// The watch is on the git directory, not on HEAD: git replaces HEAD by
/// renaming a lock file over it, which a watch on the old file never sees.
final class GitBranchWatcher {
    private nonisolated static let queue = DispatchQueue(label: "dev.beam.terminal.git-branch", qos: .utility)

    private let onChange: (String?) -> Void
    private var branch: String?
    private var source: (any DispatchSourceFileSystemObject)?

    init(folder: String, onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
        Self.queue.async { [weak self] in
            let head = GitHead.file(containing: folder)
            let branch = head.flatMap(GitHead.name(ofFile:))
            let directory = head.map { open(($0 as NSString).deletingLastPathComponent, O_EVTONLY) } ?? -1
            DispatchQueue.main.async {
                guard let self else {
                    if directory >= 0 { close(directory) }
                    return
                }
                self.report(branch)
                if let head, directory >= 0 { self.watch(directory, head: head) }
            }
        }
    }

    isolated deinit {
        source?.cancel()
    }

    private func watch(_ directory: Int32, head: String) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directory, eventMask: .write, queue: Self.queue)
        // Sendable, so the handlers do not inherit main-actor isolation:
        // they run on the background queue.
        source.setEventHandler { @Sendable [weak self] in
            let branch = GitHead.name(ofFile: head)
            DispatchQueue.main.async { self?.report(branch) }
        }
        source.setCancelHandler { @Sendable in close(directory) }
        source.resume()
        self.source = source
    }

    private func report(_ branch: String?) {
        guard branch != self.branch else { return }
        self.branch = branch
        onChange(branch)
    }
}
