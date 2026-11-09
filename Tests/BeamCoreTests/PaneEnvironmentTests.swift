import BeamCore
import Testing

struct PaneEnvironmentTests {
    let home = "/Users/me"

    @Test func launcherVariablesAreRemoved() {
        let launcher = [
            "CLAUDECODE": "1",
            "CLAUDE_CODE_CHILD_SESSION": "1",
            "CLAUDE_CODE_ENTRYPOINT": "cli",
            "CLAUDE_PID": "4242",
            "CLAUDE_EFFORT": "high",
            "CMUX_WORKSPACE_ID": "w",
            "TERM_PROGRAM": "cmux",
            "TERM_PROGRAM_VERSION": "1",
            "TERM_SESSION_ID": "s",
            "ITERM_PROFILE": "Default",
            "TMUX": "/tmp/tmux",
            "TMUX_PANE": "%1",
            "GHOSTTY_RESOURCES_DIR": "/Applications/Ghostty.app/Contents/Resources/ghostty",
            "__MISE_ORIG_PATH": "/Users/me/.cmuxterm/bin:/usr/bin",
            "__MISE_SESSION": "eAHq",
            "HOME": home,
            "LANG": "en_US.UTF-8",
            "CLAUDE_CONFIG_DIR": "/Users/me/.claude",
        ]
        #expect(
            PaneEnvironment.sanitized(launcher, home: home) == [
                "HOME": home,
                "LANG": "en_US.UTF-8",
                "CLAUDE_CONFIG_DIR": "/Users/me/.claude",
            ])
    }

    @Test func cmuxPathEntriesAreRemovedAndTheRestKeepTheirOrder() {
        let launcher = ["PATH": "/Users/me/.cmuxterm/bin:/opt/homebrew/bin:/Users/me/.cmuxterm:/usr/bin"]
        #expect(PaneEnvironment.sanitized(launcher, home: home) == ["PATH": "/opt/homebrew/bin:/usr/bin"])
    }

    @Test func cmuxAppBundlePathEntriesAreRemoved() {
        let launcher = [
            "PATH":
                "/Applications/cmux.app/Contents/Resources/bin:/usr/bin:/Users/me/Applications/cmux.app/Contents/MacOS"
        ]
        #expect(PaneEnvironment.sanitized(launcher, home: home) == ["PATH": "/usr/bin"])
    }

    @Test func similarlyNamedPathEntriesStay() {
        let launcher = ["PATH": "/Users/me/.cmuxterm-old/bin:/usr/bin"]
        #expect(PaneEnvironment.sanitized(launcher, home: home) == launcher)
    }

    @Test func paneVariablesIdentifyThePaneAndWorkspace() {
        let pane = Pane.ID()
        let workspace = Workspace.ID()
        #expect(
            PaneEnvironment.variables(pane: pane, workspace: workspace, hooks: nil) == [
                "BEAM_PANE_ID": pane.description,
                "BEAM_WORKSPACE_ID": workspace.description,
            ])
    }

    @Test func paneVariablesCarryTheAgentHooks() {
        let pane = Pane.ID()
        let hooks = AgentHooks(helper: "/Applications/Beam.app/Contents/Helpers/beam")
        let variables = PaneEnvironment.variables(pane: pane, workspace: Workspace.ID(), hooks: hooks)
        #expect(variables["BEAM_PANE_ID"] == pane.description)
        #expect(variables["BEAM_CLI"] == hooks.helper)
        #expect(variables.count == 2 + hooks.environment.count)
    }

    let integration = "/Applications/Beam.app/Contents/Resources/ghostty/shell-integration/zsh"

    /// Ghostty only adds it to a command it knows as a shell, and the pane's
    /// command is beam-attach.
    @Test func zshGetsGhosttysShellIntegration() {
        #expect(
            PaneEnvironment.shellIntegration(shell: "/bin/zsh", zdotdir: nil, directory: integration) == [
                "ZDOTDIR": integration
            ])
    }

    @Test func theUsersOwnZdotdirIsKeptForTheIntegrationToLoad() {
        #expect(
            PaneEnvironment.shellIntegration(
                shell: "/opt/homebrew/bin/zsh", zdotdir: "/Users/me/.zsh", directory: integration)
                == ["ZDOTDIR": integration, "GHOSTTY_ZSH_ZDOTDIR": "/Users/me/.zsh"])
    }

    @Test func otherShellsGetNothing() {
        for shell in ["/bin/bash", "/opt/homebrew/bin/fish", "/bin/zsh-wrapper"] {
            #expect(
                PaneEnvironment.shellIntegration(shell: shell, zdotdir: "/Users/me/.zsh", directory: integration)
                    .isEmpty)
        }
    }
}
