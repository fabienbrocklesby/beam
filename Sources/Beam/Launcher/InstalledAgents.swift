import AppKit
import BeamCore
import os

/// The agent CLIs the user's shell would find, which are the ones the
/// launcher offers.
///
/// The login shell runs once, at launch, for its `PATH`. Looking agents up on
/// that `PATH` is a few file checks, so it is redone whenever one may just
/// have been installed: when Beam comes forward, and when a command in a
/// pane finishes. All of it happens off the main thread.
final class InstalledAgents {
    private nonisolated static let queue = DispatchQueue(label: "dev.beam.terminal.agents", qos: .utility)

    /// Empty until the login shell has answered.
    private(set) var agents: Set<Agent> = []
    var onChange: (() -> Void)?
    /// The login shell's `PATH`, once it has answered.
    private(set) var path: String?

    /// Lives as long as the process, so its observer and queued work never
    /// outlive it.
    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    /// Asks the login shell for its `PATH`, then calls `then`. Beam's own
    /// `PATH` stands in when the shell fails or hangs, which still finds
    /// agents installed in the system's own folders. Asked again after an
    /// update, since mise puts each version in a folder of its own.
    func start(then: @escaping @MainActor () -> Void = {}) {
        // main.swift has already stripped what launched Beam from this.
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"] ?? "/bin/zsh"
        Self.queue.async {
            let path: String
            if let login = LoginShell.path(shell: shell, environment: environment, timeout: 10) {
                path = login
            } else {
                Logger.app.error("could not read the PATH of login shell \(shell, privacy: .public)")
                path = environment["PATH"] ?? ""
            }
            let agents = Self.agents(onPath: path)
            DispatchQueue.main.async {
                self.path = path
                self.update(agents)
                then()
            }
        }
    }

    /// Looks the agents up again on the login shell's `PATH`.
    func refresh() {
        guard let path else { return }
        Self.queue.async {
            let agents = Self.agents(onPath: path)
            DispatchQueue.main.async { self.update(agents) }
        }
    }

    private nonisolated static func agents(onPath path: String) -> Set<Agent> {
        let isExecutable = FileManager.default.isExecutableFile
        return Set(Agent.allCases.filter { $0.location(onPath: path, isExecutable: isExecutable) != nil })
    }

    private func update(_ agents: Set<Agent>) {
        guard agents != self.agents else { return }
        self.agents = agents
        onChange?()
    }
}
