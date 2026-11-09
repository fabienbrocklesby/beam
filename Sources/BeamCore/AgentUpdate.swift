/// What Beam knows about updating one agent CLI: where it is, how it was
/// installed, which version that is and which is the latest.
public struct AgentUpdate: Equatable, Sendable {
    /// The latest version, as far as its registry has said.
    public enum Latest: Equatable, Sendable {
        case unknown
        case found(Version)
        /// The registry could not be reached, or did not say.
        case failed
    }

    /// Where the login shell finds the program.
    public private(set) var program: String
    /// Nil when Beam does not know how it was installed.
    public private(set) var method: InstallMethod?
    /// What the program says it is; nil when it would not say.
    public private(set) var installed: Version?
    public var latest = Latest.unknown
    /// What was installed before the last change, which the panes running
    /// the agent then still run.
    public private(set) var outdatedVersion: Version?
    private var outdatedPanes: Set<Pane.ID> = []

    public init(program: String, method: InstallMethod?, installed: Version?) {
        self.program = program
        self.method = method
        self.installed = installed
    }

    /// The version an update brings, when it is newer than the installed one
    /// and Beam knows how to update.
    public var available: Version? {
        guard method != nil, let installed, case .found(let latest) = latest, latest > installed else { return nil }
        return latest
    }

    /// What a shell runs to update the agent.
    public var command: String? { method?.updateCommand(program: program) }

    /// Takes in a fresh look at the program. When its version has changed,
    /// the panes in `running` keep the one they started with until they are
    /// restarted.
    public mutating func inspected(_ fresh: AgentUpdate, running: Set<Pane.ID>) {
        // The latest version came from the old method's registry.
        if fresh.method != method { latest = .unknown }
        if let installed, let new = fresh.installed, new != installed {
            outdatedVersion = installed
            outdatedPanes = running
        }
        program = fresh.program
        method = fresh.method
        installed = fresh.installed
    }

    /// Those of `running` that still run `outdatedVersion`.
    public func outdated(running: Set<Pane.ID>) -> Set<Pane.ID> {
        outdatedPanes.intersection(running)
    }
}
