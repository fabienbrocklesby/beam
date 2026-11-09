import BeamCore
import Foundation

/// The installed and latest version of each agent CLI the login shell finds,
/// how it was installed, and so how to update it.
///
/// Every look is an event, never a timer. Installed versions are read at
/// launch, when the Agents menu opens and after an update Beam ran. Latest
/// versions are asked for at launch and by Check for Updates, and when the
/// menu opens if the last answer is over an hour old or was missing.
/// Programs run and registries are asked off the main thread.
final class AgentUpdates {
    private nonisolated static let queue = DispatchQueue(label: "dev.beam.terminal.updates", qos: .utility)
    /// Ephemeral, so nothing Beam asks is cached on disk.
    private nonisolated static let session = URLSession(configuration: .ephemeral)
    private static let checkInterval = Duration.seconds(60 * 60)

    private let installedAgents: InstalledAgents
    /// The installed agents'. Empty until the first look.
    private(set) var updates: [Agent: AgentUpdate] = [:]
    /// Whether Beam has looked for the agents yet.
    private(set) var hasLooked = false
    /// Whether the registries are being asked.
    private(set) var isChecking = false
    private var lastCheck: ContinuousClock.Instant?
    var onChange: (() -> Void)?
    /// The panes running `agent`, which keep its version when it changes.
    var panesRunning: (Agent) -> Set<Pane.ID> = { _ in [] }

    /// Lives as long as the process, so the work it queues never outlives it.
    init(installedAgents: InstalledAgents) {
        self.installedAgents = installedAgents
    }

    /// The agents with an update waiting, in `Agent` order.
    var available: [Agent] {
        Agent.allCases.filter { updates[$0]?.available != nil }
    }

    /// How many panes still run what `agent` was before its last update.
    func outdatedPanes(of agent: Agent) -> Int {
        updates[agent]?.outdated(running: panesRunning(agent)).count ?? 0
    }

    /// At launch, once the login shell's `PATH` is known.
    func start() {
        inspect { self.check() }
    }

    /// The Agents menu is opening.
    func menuWillOpen() {
        inspect { self.checkIfNeeded() }
    }

    /// An update Beam ran has finished. mise puts each version in a folder of
    /// its own, so the login shell's `PATH` is read again first.
    func updateFinished() {
        installedAgents.start { self.inspect { self.checkIfNeeded() } }
    }

    /// Asks each installed agent's registry for its latest version.
    func check() {
        guard !isChecking else { return }
        let methods = updates.compactMapValues(\.method)
        guard !methods.isEmpty else { return }
        isChecking = true
        lastCheck = .now
        onChange?()
        Task {
            var latest: [Agent: Version?] = [:]
            await withTaskGroup(of: (Agent, Version?).self) { group in
                for (agent, method) in methods {
                    group.addTask { (agent, await Self.latestVersion(method)) }
                }
                for await (agent, version) in group { latest[agent] = version }
            }
            isChecking = false
            for (agent, version) in latest where updates[agent]?.method == methods[agent] {
                updates[agent]?.latest = version.map(AgentUpdate.Latest.found) ?? .failed
            }
            onChange?()
        }
    }

    private func checkIfNeeded() {
        let stale = lastCheck.map { $0.duration(to: .now) > Self.checkInterval } ?? true
        let missing = updates.values.contains { update in
            if case .found = update.latest { return false }
            return update.method != nil
        }
        if stale || missing { check() }
    }

    /// Looks the agents up on the login shell's `PATH` and reads what each
    /// is, then calls `then`.
    private func inspect(then: @escaping @MainActor () -> Void) {
        guard let path = installedAgents.path else { return }
        let environment = ProcessInfo.processInfo.environment.merging(["PATH": path]) { $1 }
        Self.queue.async {
            let found = Self.inspect(path: path, environment: environment)
            DispatchQueue.main.async {
                self.apply(found)
                then()
            }
        }
    }

    private nonisolated static func inspect(path: String, environment: [String: String]) -> [Agent: AgentUpdate] {
        var found: [Agent: AgentUpdate] = [:]
        for agent in Agent.allCases {
            guard let program = agent.location(onPath: path, isExecutable: FileManager.default.isExecutableFile) else {
                continue
            }
            let resolved = URL(filePath: program).resolvingSymlinksInPath().path
            found[agent] = AgentUpdate(
                program: program, method: InstallMethod(resolvedPath: resolved),
                installed: Version.reported(by: program, environment: environment, timeout: 10))
        }
        return found
    }

    private func apply(_ found: [Agent: AgentUpdate]) {
        var next: [Agent: AgentUpdate] = [:]
        for (agent, fresh) in found {
            var update = updates[agent] ?? fresh
            update.inspected(fresh, running: panesRunning(agent))
            next[agent] = update
        }
        let changed = next != updates || !hasLooked
        hasLooked = true
        updates = next
        if changed { onChange?() }
    }

    @concurrent private nonisolated static func latestVersion(_ method: InstallMethod) async -> Version? {
        guard let source = method.latestSource else { return nil }
        let request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (answer, response) = try? await session.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return method.latestVersion(from: answer)
    }
}
