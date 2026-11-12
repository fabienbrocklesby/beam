import AppKit

// The app a file opens in when the user takes it out of Beam. Beam never
// hands a file it can show to `open(_:)`: once Beam is the file's default
// app, it would come straight back.
extension NSWorkspace {
    /// The app that opens `url` outside Beam, and its name: the file's
    /// default app unless that is a copy of Beam, then the first other app
    /// Launch Services lists for it. Asks Launch Services, so keep it off
    /// the main thread.
    nonisolated func applicationOutsideBeam(toOpen url: URL) -> (url: URL, name: String)? {
        let copies = Bundle.main.bundleIdentifier.map { urlsForApplications(withBundleIdentifier: $0) } ?? []
        let beams = Set((copies + [Bundle.main.bundleURL]).map(\.standardizedFileURL))
        let apps = [urlForApplication(toOpen: url)].compactMap { $0 } + urlsForApplications(toOpen: url)
        guard let app = apps.first(where: { !beams.contains($0.standardizedFileURL) }) else { return nil }
        let name = FileManager.default.displayName(atPath: app.path)
        return (app, name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }
}
