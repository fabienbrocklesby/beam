import Foundation

/// The environment a pane's processes start with.
public enum PaneEnvironment {
    /// Variables that describe whatever launched Beam (an agent session,
    /// another terminal, a multiplexer) rather than the user. Left in, they
    /// make a pane's programs think they run inside that launcher. libghostty
    /// sets the `TERM_*` and `GHOSTTY_*` variables a pane needs itself; an
    /// inherited `GHOSTTY_RESOURCES_DIR` would even point it at another install.
    /// `__MISE_*` is the launcher shell's mise session, whose saved `PATH` would
    /// bring the launcher's entries back when mise activates in the pane.
    private static let launcherPrefixes = [
        "CLAUDE_CODE_", "CMUX_", "GHOSTTY_", "ITERM_", "TERM_PROGRAM", "TMUX", "__MISE_",
    ]
    private static let launcherNames: Set = ["CLAUDECODE", "CLAUDE_EFFORT", "CLAUDE_PID", "TERM_SESSION_ID"]

    /// `environment` without the launcher's variables or cmux's `PATH` entries:
    /// its per-session shims (which wrap `claude` and `codex`) and its app
    /// bundle's tools (which shadow `open`).
    public static func sanitized(_ environment: [String: String], home: String) -> [String: String] {
        var result = environment.filter { name, _ in
            !launcherNames.contains(name) && !launcherPrefixes.contains { name.hasPrefix($0) }
        }
        if let path = result["PATH"] {
            let cmux = home + "/.cmuxterm"
            result["PATH"] =
                path
                .split(separator: ":", omittingEmptySubsequences: false)
                .filter { $0 != cmux && !$0.hasPrefix(cmux + "/") && !$0.contains("/cmux.app/") }
                .joined(separator: ":")
        }
        return result
    }

    /// Beam's own variables for one pane, so programs and agent hooks can say
    /// which pane they run in, and with `hooks`, where to report it.
    public static func variables(pane: Pane.ID, workspace: Workspace.ID, hooks: AgentHooks?) -> [String: String] {
        ["BEAM_PANE_ID": pane.description, "BEAM_WORKSPACE_ID": workspace.description]
            .merging(hooks?.environment ?? [:]) { $1 }
    }

    /// What a pane's zsh needs for Ghostty's shell integration (working
    /// directory, prompt marks, titles), which Ghostty only adds to a command
    /// it knows as a shell, and a pane's command is beam-attach. As Ghostty
    /// does: `ZDOTDIR` names the bundled integration `directory`, whose files
    /// load the user's own from `GHOSTTY_ZSH_ZDOTDIR` when they had a
    /// `zdotdir`. Other shells get nothing.
    public static func shellIntegration(shell: String, zdotdir: String?, directory: String) -> [String: String] {
        guard (shell as NSString).lastPathComponent == "zsh" else { return [:] }
        var variables = ["ZDOTDIR": directory]
        if let zdotdir { variables["GHOSTTY_ZSH_ZDOTDIR"] = zdotdir }
        return variables
    }
}
