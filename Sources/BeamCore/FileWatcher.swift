import Darwin
import Dispatch
import Foundation

/// Watches the file at one path. Calls back on the main queue once it is
/// watching, and again whenever the file changes: written in place, replaced
/// by a file renamed over it, deleted, renamed away, or created again.
///
/// Agents and editors do all of those: Codex's apply_patch and vim write in
/// place, which only the file's own vnode sees; Claude Code's Write and Edit
/// and NSDocument rename a new file over it, and git checkout deletes and
/// creates it, which its folder sees. So both are watched. Each burst of
/// events becomes one look at the path's inode, size and modification time,
/// off the main thread, and a call only when they changed, so other files in
/// a busy folder cost a `stat`, not a reload.
@MainActor
public final class FileWatcher {
    private struct Signature: Equatable, Sendable {
        var inode: UInt64
        var size: Int64
        var seconds: Int
        var nanoseconds: Int

        init(_ info: stat) {
            inode = UInt64(info.st_ino)
            size = Int64(info.st_size)
            seconds = info.st_mtimespec.tv_sec
            nanoseconds = info.st_mtimespec.tv_nsec
        }
    }

    /// What one look found, with descriptors it opened for the folder and
    /// for a file not watched yet; -1 for none.
    private struct Look: Sendable {
        var signature: Signature?
        var folder: Int32 = -1
        var file: Int32 = -1

        func close() {
            if folder >= 0 { Darwin.close(folder) }
            if file >= 0 { Darwin.close(file) }
        }
    }

    private nonisolated static let queue = DispatchQueue(label: "dev.beam.terminal.file-watcher", qos: .userInitiated)

    private let path: String
    private let onChange: () -> Void
    private var folder: (any DispatchSourceFileSystemObject)?
    private var file: (any DispatchSourceFileSystemObject)?
    private var watchedInode: UInt64?
    private var last: Signature?
    private var hasLooked = false
    private var isLooking = false
    /// Events came while a look was out, which may have missed them.
    private var looksAgain = false
    private var isCancelled = false

    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        look()
    }

    isolated deinit {
        cancel()
    }

    /// Stops watching for good.
    public func cancel() {
        isCancelled = true
        folder?.cancel()
        file?.cancel()
        folder = nil
        file = nil
    }

    private func eventArrived() {
        guard !isLooking else {
            looksAgain = true
            return
        }
        look()
    }

    private func look() {
        isLooking = true
        let path = path
        let watched = watchedInode
        let opensFolder = folder == nil
        Self.queue.async { [weak self] in
            let found = Self.look(at: path, watching: watched, opensFolder: opensFolder)
            DispatchQueue.main.async {
                guard let self else { return found.close() }
                self.settle(found)
            }
        }
    }

    private nonisolated static func look(at path: String, watching inode: UInt64?, opensFolder: Bool) -> Look {
        var found = Look()
        if opensFolder { found.folder = open((path as NSString).deletingLastPathComponent, O_EVTONLY) }
        var info = stat()
        guard stat(path, &info) == 0 else { return found }
        found.signature = Signature(info)
        guard found.signature?.inode != inode else { return found }
        found.file = open(path, O_EVTONLY)
        // Replaced again since the stat, the descriptor's file is the one
        // watched and looked at.
        if found.file >= 0, fstat(found.file, &info) == 0 { found.signature = Signature(info) }
        return found
    }

    private func settle(_ found: Look) {
        isLooking = false
        guard !isCancelled else { return found.close() }
        if found.folder >= 0 {
            folder = source(watching: found.folder, for: .write)
        }
        if found.file >= 0 {
            file?.cancel()
            file = source(watching: found.file, for: [.write, .extend, .attrib, .delete, .rename, .revoke])
            watchedInode = found.signature?.inode
        } else if found.signature == nil {
            file?.cancel()
            file = nil
            watchedInode = nil
        }
        let changed = !hasLooked || found.signature != last
        hasLooked = true
        last = found.signature
        if looksAgain {
            looksAgain = false
            look()
        }
        if changed { onChange() }
    }

    private func source(
        watching descriptor: Int32, for events: DispatchSource.FileSystemEvent
    ) -> any DispatchSourceFileSystemObject {
        let source = WatchedDescriptor(descriptor).makeFileSystemObjectSource(eventMask: events)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.eventArrived() }
        }
        source.resume()
        return source
    }
}
