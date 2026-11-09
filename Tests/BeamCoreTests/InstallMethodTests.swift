import BeamCore
import Foundation
import Testing

struct InstallMethodTests {
    // MARK: Telling the method from where the program lives

    @Test func aHomebrewCaskLivesInTheCaskroom() {
        #expect(
            InstallMethod(resolvedPath: "/opt/homebrew/Caskroom/claude-code@latest/2.1.281/claude")
                == .homebrewCask(token: "claude-code@latest"))
        #expect(
            InstallMethod(resolvedPath: "/usr/local/Caskroom/codex/0.167.0/codex-aarch64-apple-darwin")
                == .homebrewCask(token: "codex"))
    }

    /// A formula built from an npm package keeps it inside the Cellar, and
    /// Homebrew is still what updates it.
    @Test func aHomebrewFormulaLivesInTheCellar() {
        let gemini =
            "/opt/homebrew/Cellar/gemini-cli/0.67.0/libexec/lib/node_modules/@google/gemini-cli/bundle/gemini.js"
        #expect(InstallMethod(resolvedPath: gemini) == .homebrewFormula(name: "gemini-cli"))
    }

    @Test func miseKeepsEachNpmPackageInItsOwnInstallFolder() {
        let home = "/Users/me/.local/share/mise/installs"
        #expect(
            InstallMethod(resolvedPath: "\(home)/npm-openai-codex/0.166.0/lib/node_modules/@openai/codex/bin/codex.js")
                == .mise(package: "@openai/codex"))
        #expect(
            InstallMethod(resolvedPath: "\(home)/npm-left-pad/1.3.0/lib/node_modules/left-pad/bin/cli.js")
                == .mise(package: "left-pad"))
    }

    /// mise's Node is a plain Node, so what is installed globally with its
    /// npm is npm's to update.
    @Test func npmGlobalPackagesLiveInTheirPrefixesLib() {
        #expect(
            InstallMethod(resolvedPath: "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js")
                == .npm(package: "@openai/codex"))
        #expect(
            InstallMethod(
                resolvedPath:
                    "/Users/me/.local/share/mise/installs/node/24.22.2/lib/node_modules/@moonshot-ai/kimi-code/bin/kimi"
            ) == .npm(package: "@moonshot-ai/kimi-code"))
        #expect(
            InstallMethod(
                resolvedPath:
                    "/Users/me/.nvm/versions/node/v22.1.0/lib/node_modules/@google/gemini-cli/dist/index.js")
                == .npm(package: "@google/gemini-cli"))
    }

    @Test func uvKeepsEachToolInItsOwnEnvironment() {
        #expect(
            InstallMethod(resolvedPath: "/Users/me/.local/share/uv/tools/kimi-cli/bin/kimi")
                == .uv(tool: "kimi-cli"))
    }

    @Test func claudesInstallerKeepsEveryVersionInOneFolder() {
        #expect(InstallMethod(resolvedPath: "/Users/me/.local/share/claude/versions/2.1.319") == .claudeInstaller)
    }

    /// Their global folders are not npm's, and npm would install a second
    /// copy rather than update theirs.
    @Test func otherPackageManagersAndHandInstallsAreUnknown() {
        #expect(
            InstallMethod(resolvedPath: "/Users/me/.bun/install/global/node_modules/@openai/codex/bin/codex.js")
                == nil)
        #expect(
            InstallMethod(resolvedPath: "/Users/me/Library/pnpm/global/5/node_modules/@openai/codex/bin/codex.js")
                == nil)
        #expect(
            InstallMethod(resolvedPath: "/Users/me/.local/share/mise/installs/aqua-openai-codex/0.1/codex") == nil)
        #expect(InstallMethod(resolvedPath: "/usr/local/bin/kimi") == nil)
        #expect(InstallMethod(resolvedPath: "/opt/homebrew/Caskroom/codex") == nil)
        #expect(InstallMethod(resolvedPath: "/opt/homebrew/lib/node_modules") == nil)
        #expect(InstallMethod(resolvedPath: "") == nil)
    }

    // MARK: Updating

    @Test func eachMethodUpdatesWithItsOwnTool() {
        let program = "/opt/homebrew/bin/agent"
        #expect(
            InstallMethod.homebrewCask(token: "claude-code@latest").updateCommand(program: program)
                == "brew upgrade --cask claude-code@latest")
        #expect(
            InstallMethod.homebrewFormula(name: "gemini-cli").updateCommand(program: program)
                == "brew upgrade gemini-cli")
        #expect(
            InstallMethod.mise(package: "@openai/codex").updateCommand(program: program)
                == "mise upgrade npm:@openai/codex")
        #expect(
            InstallMethod.npm(package: "@google/gemini-cli").updateCommand(program: program)
                == "npm install -g @google/gemini-cli@latest")
        #expect(InstallMethod.uv(tool: "kimi-cli").updateCommand(program: program) == "uv tool upgrade kimi-cli")
    }

    /// Typed as `claude update`, Beam would take it for Claude itself: give it
    /// hooks, and resume it as a conversation on relaunch.
    @Test func claudesInstallerUpdatesThroughTheProgramByItsPath() {
        let command = InstallMethod.claudeInstaller.updateCommand(program: "/Users/me/.local/bin/claude")
        #expect(command == "/Users/me/.local/bin/claude update")
        #expect(Agent(command: command) == nil)
        #expect(Agent.resuming(command) == command)
    }

    /// Names come from folder names, and are typed into a shell.
    @Test func namesAreQuotedForTheShell() {
        #expect(InstallMethod.homebrewCask(token: "a;b").updateCommand(program: "") == #"brew upgrade --cask a\;b"#)
        #expect(InstallMethod.npm(package: "$(x)").updateCommand(program: "") == #"npm install -g \$\(x\)@latest"#)
        #expect(
            InstallMethod.claudeInstaller.updateCommand(program: "/My Tools/claude") == #"/My\ Tools/claude update"#)
    }

    @Test func eachMethodIsNamedForTheMenu() {
        #expect(InstallMethod.homebrewCask(token: "codex").name == "Homebrew")
        #expect(InstallMethod.homebrewFormula(name: "gemini-cli").name == "Homebrew")
        #expect(InstallMethod.mise(package: "@openai/codex").name == "mise")
        #expect(InstallMethod.npm(package: "@openai/codex").name == "npm")
        #expect(InstallMethod.uv(tool: "kimi-cli").name == "uv")
        #expect(InstallMethod.claudeInstaller.name == "Claude's installer")
    }

    // MARK: The latest version

    @Test func eachMethodAsksItsOwnRegistry() {
        #expect(
            InstallMethod.homebrewCask(token: "claude-code@latest").latestSource?.absoluteString
                == "https://formulae.brew.sh/api/cask/claude-code@latest.json")
        #expect(
            InstallMethod.homebrewFormula(name: "gemini-cli").latestSource?.absoluteString
                == "https://formulae.brew.sh/api/formula/gemini-cli.json")
        #expect(
            InstallMethod.mise(package: "@openai/codex").latestSource?.absoluteString
                == "https://registry.npmjs.org/@openai/codex/latest")
        #expect(
            InstallMethod.npm(package: "@google/gemini-cli").latestSource?.absoluteString
                == "https://registry.npmjs.org/@google/gemini-cli/latest")
        #expect(
            InstallMethod.uv(tool: "kimi-cli").latestSource?.absoluteString == "https://pypi.org/pypi/kimi-cli/json")
        #expect(
            InstallMethod.claudeInstaller.latestSource?.absoluteString
                == "https://registry.npmjs.org/@anthropic-ai/claude-code/latest")
    }

    /// Trimmed from real answers from each registry.
    @Test func readsTheLatestVersionFromEachRegistrysAnswer() {
        let cask = #"{"token":"claude-code@latest","version":"2.1.319","auto_updates":null}"#
        #expect(
            InstallMethod.homebrewCask(token: "claude-code@latest").latestVersion(from: Data(cask.utf8))?.description
                == "2.1.319")

        let formula = #"{"name":"gemini-cli","versions":{"stable":"0.67.0","head":null,"bottle":true},"revision":1}"#
        #expect(
            InstallMethod.homebrewFormula(name: "gemini-cli").latestVersion(from: Data(formula.utf8))?.description
                == "0.67.0")

        let npm = #"{"name":"@openai/codex","version":"0.167.0","bin":{"codex":"bin/codex.js"}}"#
        #expect(
            InstallMethod.npm(package: "@openai/codex").latestVersion(from: Data(npm.utf8))?.description == "0.167.0")
        #expect(
            InstallMethod.mise(package: "@openai/codex").latestVersion(from: Data(npm.utf8))?.description == "0.167.0")
        #expect(InstallMethod.claudeInstaller.latestVersion(from: Data(npm.utf8))?.description == "0.167.0")

        let pypi = #"{"info":{"name":"kimi-cli","version":"1.52.0"},"releases":{}}"#
        #expect(InstallMethod.uv(tool: "kimi-cli").latestVersion(from: Data(pypi.utf8))?.description == "1.52.0")
    }

    @Test func anAnswerWithoutAVersionGivesNone() {
        let method = InstallMethod.npm(package: "@openai/codex")
        #expect(method.latestVersion(from: Data(#"{"error":"Not found"}"#.utf8)) == nil)
        #expect(method.latestVersion(from: Data("<html>".utf8)) == nil)
        #expect(method.latestVersion(from: Data(#"{"version":"latest"}"#.utf8)) == nil)
    }
}
