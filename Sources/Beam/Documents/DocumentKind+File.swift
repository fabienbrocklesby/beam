import BeamCore
import Foundation
import UniformTypeIdentifiers

extension DocumentKind {
    /// The kind of the file at `url`, by the type its extension names.
    /// Asks Launch Services, not the disk.
    nonisolated init(file url: URL, chosen: Bool) {
        let type = UTType(filenameExtension: url.pathExtension)
        let types = type.map { Set([$0.identifier] + $0.supertypes.map(\.identifier)) } ?? []
        self.init(path: url.path, types: types, chosen: chosen)
    }
}
