import BeamCore
import Foundation
import os

/// Keeps `state.json` in step with the workspace store without blocking the
/// main thread. Every change is handed to `save`; writes happen one at a
/// time on a background queue, and changes that arrive during a write
/// collapse into the next one, so a divider drag costs a few writes rather
/// than one per mouse event.
final class StateSaver {
    private nonisolated static let queue = DispatchQueue(label: "dev.beam.terminal.state", qos: .utility)

    private let file: StateFile
    /// The newest store not yet handed to the queue.
    private var pending: WorkspaceStore?
    private var isWriting = false

    init(file: StateFile) {
        self.file = file
    }

    /// Reads the saved store off the main thread and delivers it ready for
    /// a new launch, with whether it came from the file. A file that cannot
    /// be read is moved aside and logged, and Beam starts as if nothing was
    /// saved.
    static func load(_ file: StateFile, then deliver: @escaping @MainActor (WorkspaceStore, Bool) -> Void) {
        queue.async {
            var store: WorkspaceStore
            var loaded = false
            do {
                let saved = try file.load()
                loaded = saved != nil
                store = saved ?? WorkspaceStore()
            } catch {
                Logger.app.error("could not read \(file.url.path, privacy: .public): \(error, privacy: .public)")
                do {
                    try file.moveAside()
                } catch {
                    Logger.app.error("could not move the unreadable state aside: \(error, privacy: .public)")
                }
                store = WorkspaceStore()
            }
            store.prepareForLaunch(home: NSHomeDirectory()) { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            DispatchQueue.main.async { [store, loaded] in deliver(store, loaded) }
        }
    }

    func save(_ store: WorkspaceStore) {
        pending = store
        if !isWriting { writeNext() }
    }

    /// Waits for the write in progress and writes whatever is newer. Blocks,
    /// so only for when the app is about to exit.
    func flush() {
        Self.queue.sync {}
        guard let store = pending else { return }
        pending = nil
        Self.write(store, to: file)
    }

    private func writeNext() {
        guard let store = pending else {
            isWriting = false
            return
        }
        pending = nil
        isWriting = true
        let file = file
        Self.queue.async { [weak self] in
            Self.write(store, to: file)
            DispatchQueue.main.async { self?.writeNext() }
        }
    }

    private nonisolated static func write(_ store: WorkspaceStore, to file: StateFile) {
        do {
            try file.save(store)
        } catch {
            Logger.app.error("could not save \(file.url.path, privacy: .public): \(error, privacy: .public)")
        }
    }
}
