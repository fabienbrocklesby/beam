/// The files each pane's agent has touched in the turn it is on, so the
/// names its reply ends the turn with can be found where it put them: an
/// agent writes a screenshot to a scratchpad and names it by its name alone.
public struct TurnFiles: Equatable, Sendable {
    /// What a finished turn named, with what its tools touched, for
    /// `FileResolver.paths`.
    public struct Lookup: Equatable, Sendable {
        public var names: [String]
        public var directory: String?
        /// Absolute paths, oldest first.
        public var touched: [String]

        public init(names: [String], directory: String?, touched: [String]) {
            self.names = names
            self.directory = directory
            self.touched = touched
        }
    }

    /// Most files a turn keeps, the latest: past this many, the agent is
    /// on a job no preview is for.
    private static let limit = 256

    private let home: String
    private var touched: [Pane.ID: [String]] = [:]

    public init(home: String) {
        self.home = home
    }

    /// Takes in `report`, and returns what to look for when it ends a turn:
    /// even nothing, so a reply that names no files replaces the last one's.
    @discardableResult
    public mutating func record(_ report: AgentReport) -> Lookup? {
        let pane = report.pane
        switch report.event {
        case .working:
            guard let files = report.files else { return nil }
            var paths = touched[pane] ?? []
            for name in files.names {
                guard let path = absolute(name, in: files.directory), !paths.contains(path) else { continue }
                paths.append(path)
            }
            touched[pane] = Array(paths.suffix(Self.limit))
            return nil
        case .done:
            let paths = touched.removeValue(forKey: pane) ?? []
            return Lookup(names: report.files?.names ?? [], directory: report.files?.directory, touched: paths)
        case .started, .ended:
            touched[pane] = nil
            return nil
        case .waiting, .idle:
            return nil
        }
    }

    /// Drops what `pane` touched: it has closed.
    public mutating func forget(_ pane: Pane.ID) {
        touched[pane] = nil
    }

    /// `name` as an absolute path, or nil when it is no path or is relative
    /// with no directory to start from.
    private func absolute(_ name: String, in directory: String?) -> String? {
        guard case .file(let path) = FileMention(name, home: home) else { return nil }
        if path.hasPrefix("/") { return path }
        return directory.map { $0 + "/" + path }
    }
}
