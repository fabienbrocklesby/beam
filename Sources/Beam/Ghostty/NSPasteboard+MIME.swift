import AppKit
import BeamCore
import UniformTypeIdentifiers

extension NSPasteboard {
    /// The pasteboard's contents as `mimeType`. Text pastes become
    /// shell-escaped paths when files were copied, so dropping a screenshot
    /// into an agent prompt just works.
    func data(forMIMEType mimeType: String) -> Data? {
        guard mimeType == "text/plain" else {
            return PasteboardType(mimeType: mimeType).flatMap { data(forType: $0) }
        }
        let strings = (pasteboardItems ?? []).compactMap { item -> String? in
            if let plist = item.propertyList(forType: .fileURL),
                let url = NSURL(pasteboardPropertyList: plist, ofType: .fileURL) as URL?,
                url.isFileURL
            {
                return Shell.escape(url.path)
            }
            return item.string(forType: .string)
        }
        return strings.isEmpty ? nil : Data(strings.joined(separator: " ").utf8)
    }

    func availableMIMETypes() -> [String] {
        var result: [String] = []
        if string(forType: .string) != nil || types?.contains(.fileURL) == true {
            result.append("text/plain")
        }
        for type in types ?? [] {
            if let mime = UTType(type.rawValue)?.preferredMIMEType, !result.contains(mime) {
                result.append(mime)
            }
        }
        return result
    }
}

extension NSPasteboard.PasteboardType {
    init?(mimeType: String) {
        if mimeType == "text/plain" {
            self = .string
            return
        }
        guard let type = UTType(mimeType: mimeType) else { return nil }
        self.init(type.identifier)
    }
}
