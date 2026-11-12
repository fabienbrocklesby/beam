import AppKit
import UniformTypeIdentifiers
import os

// Beam > Make Beam the Default App…. macOS sets a default app without asking
// the user, so Beam asks first, then says what Finder will do.
extension AppDelegate {
    /// The files Beam offers to open, as the alerts name them.
    private nonisolated static let defaultKinds = [
        (name: "PDFs", type: "com.adobe.pdf"),
        (name: "Markdown", type: "net.daringfireball.markdown"),
        (name: "plain text", type: "public.plain-text"),
    ]

    @objc func makeDefaultApp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Make Beam the default app for PDFs, Markdown and plain text?"
        alert.informativeText = """
            Finder will open them in Beam. To change one back, choose Get Info on a \
            file in Finder, pick an app under Open With, then Change All.
            """
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let beam = Bundle.main.bundleURL
        Task {
            let results = await Self.makeDefault(beam)
            Self.report(results, beam: beam)
        }
    }

    /// Makes `beam` the default for each kind, then asks which app opens it:
    /// a default names a bundle ID and a version, so at equal versions
    /// Launch Services can pick another copy of Beam. Both ask Launch
    /// Services, so this runs off the main thread.
    private nonisolated static func makeDefault(_ beam: URL) async -> [(name: String, opener: Result<URL?, any Error>)]
    {
        let workspace = NSWorkspace.shared
        var results: [(name: String, opener: Result<URL?, any Error>)] = []
        for kind in defaultKinds {
            guard let type = UTType(kind.type) else {
                results.append((kind.name, .failure(CocoaError(.featureUnsupported))))
                continue
            }
            do {
                try await workspace.setDefaultApplication(at: beam, toOpen: type)
                results.append((kind.name, .success(workspace.urlForApplication(toOpen: type))))
            } catch {
                Logger.app.error("could not make Beam the default for \(kind.type, privacy: .public): \(error)")
                results.append((kind.name, .failure(error)))
            }
        }
        return results
    }

    private static func report(_ results: [(name: String, opener: Result<URL?, any Error>)], beam: URL) {
        var failed: [String] = []
        var notes: [String] = []
        for (name, opener) in results {
            switch opener {
            case .failure(let error):
                failed.append(name)
                // One cause usually fails all three.
                if !notes.contains(error.localizedDescription) { notes.append(error.localizedDescription) }
            case .success(let app?) where app.standardizedFileURL != beam.standardizedFileURL:
                notes.append("\((app.path as NSString).abbreviatingWithTildeInPath) opens \(name).")
            case .success:
                break
            }
        }
        let alert = NSAlert()
        alert.messageText =
            failed.isEmpty
            ? "Beam is now the default app for PDFs, Markdown and plain text."
            : "Beam could not be made the default app for \(failed.formatted(.list(type: .and)))."
        alert.informativeText = notes.joined(separator: "\n")
        alert.runModal()
    }
}
