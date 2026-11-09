import BeamCore

/// Something the launcher opens in a new pane: an agent, or a plain shell.
enum LauncherEntry: Hashable {
    case agent(Agent)
    case shell

    /// In the order the title bar, the Shell menu and the switcher list them.
    static let all = Agent.allCases.map(LauncherEntry.agent) + [.shell]

    var name: String {
        switch self {
        case .agent(let agent): agent.name
        case .shell: "Shell"
        }
    }

    var title: String { "New \(name) Pane" }

    /// Typed into the new pane's shell; a plain shell gets nothing.
    var command: String? {
        switch self {
        case .agent(let agent): agent.command
        case .shell: nil
        }
    }
}
