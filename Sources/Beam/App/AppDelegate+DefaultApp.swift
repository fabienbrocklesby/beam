import AppKit
import BeamCore
import UniformTypeIdentifiers
import os

// Beam > Make Beam the Default App…. macOS replaces some defaults without
// asking the user, so Beam asks first, then says what Finder will do.
extension AppDelegate {
    private typealias Outcomes = [(kind: String, outcome: DefaultAppReport.Outcome)]

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
            Finder will open them in Beam. macOS may ask you to confirm each one. To change \
            one back, choose Get Info on a file in Finder, pick an app under Open With, then Change All.
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

    /// Makes `beam` the default for each kind, then asks which app opens it.
    /// Both ask Launch Services, so this runs off the main thread.
    private nonisolated static func makeDefault(_ beam: URL) async -> Outcomes {
        let workspace = NSWorkspace.shared
        var outcomes: Outcomes = []
        for kind in defaultKinds {
            guard let type = UTType(kind.type) else {
                outcomes.append((kind.name, .failed("macOS does not know the type \(kind.type).")))
                continue
            }
            do {
                try await workspace.setDefaultApplication(at: beam, toOpen: type)
                let opener = workspace.urlForApplication(toOpen: type)
                outcomes.append((kind.name, opener.map { .opens($0.standardizedFileURL.path) } ?? .kept))
            } catch {
                Logger.app.error("could not make Beam the default for \(kind.type, privacy: .public): \(error)")
                outcomes.append((kind.name, DefaultAppReport.Outcome(error)))
            }
        }
        return outcomes
    }

    private static func report(_ outcomes: Outcomes, beam: URL) {
        let report = DefaultAppReport(outcomes, beam: beam.standardizedFileURL.path)
        let alert = NSAlert()
        alert.messageText = report.message
        alert.informativeText = report.details
        alert.runModal()
    }
}
