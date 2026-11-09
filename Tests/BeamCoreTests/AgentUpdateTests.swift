import BeamCore
import Testing

struct AgentUpdateTests {
    let cask = InstallMethod.homebrewCask(token: "claude-code@latest")

    func version(_ text: String) throws -> Version { try #require(Version(in: text)) }

    @Test func aNewerLatestVersionIsAnUpdate() throws {
        var update = AgentUpdate(program: "/opt/homebrew/bin/claude", method: cask, installed: try version("2.1.281"))
        #expect(update.available == nil)
        update.latest = .found(try version("2.1.319"))
        #expect(update.available == (try version("2.1.319")))
        #expect(update.command == "brew upgrade --cask claude-code@latest")
    }

    @Test func theSameOrAnOlderLatestVersionIsNot() throws {
        var update = AgentUpdate(program: "/opt/homebrew/bin/claude", method: cask, installed: try version("2.1.319"))
        update.latest = .found(try version("2.1.319"))
        #expect(update.available == nil)
        update.latest = .found(try version("2.1.318"))
        #expect(update.available == nil)
        update.latest = .failed
        #expect(update.available == nil)
    }

    /// Without a version to compare or a way to update, there is nothing to
    /// offer.
    @Test func anUnknownVersionOrMethodHasNoUpdate() throws {
        var unversioned = AgentUpdate(program: "/opt/homebrew/bin/claude", method: cask, installed: nil)
        unversioned.latest = .found(try version("2.1.319"))
        #expect(unversioned.available == nil)

        var unknown = AgentUpdate(program: "/usr/local/bin/kimi", method: nil, installed: try version("1.0.0"))
        unknown.latest = .found(try version("2.0.0"))
        #expect(unknown.available == nil)
        #expect(unknown.command == nil)
    }

    @Test func panesRunningTheAgentWhenItsVersionChangesStillRunTheOldOne() throws {
        let one = Pane.ID()
        let two = Pane.ID()
        let three = Pane.ID()
        var update = AgentUpdate(program: "/opt/homebrew/bin/claude", method: cask, installed: try version("2.1.281"))
        #expect(update.outdated(running: [one, two]).isEmpty)

        update.inspected(
            AgentUpdate(program: "/opt/homebrew/bin/claude", method: cask, installed: try version("2.1.319")),
            running: [one, two])
        #expect(update.installed == (try version("2.1.319")))
        #expect(update.outdatedVersion == (try version("2.1.281")))
        // Two stopped, and three started on the new version.
        #expect(update.outdated(running: [one, three]) == [one])
    }

    @Test func aSecondLookAtTheSameVersionChangesNothing() throws {
        let one = Pane.ID()
        let installed = AgentUpdate(
            program: "/opt/homebrew/bin/claude", method: cask, installed: try version("2.1.281"))
        var update = installed
        update.latest = .found(try version("2.1.319"))
        update.inspected(installed, running: [one])
        #expect(update.outdated(running: [one]).isEmpty)
        #expect(update.latest == .found(try version("2.1.319")))
    }

    /// The latest version came from the old method's registry.
    @Test func anAgentInstalledAnotherWayIsCheckedAgain() throws {
        var update = AgentUpdate(program: "/opt/homebrew/bin/claude", method: cask, installed: try version("2.1.281"))
        update.latest = .found(try version("2.1.319"))
        update.inspected(
            AgentUpdate(
                program: "/Users/me/.local/bin/claude", method: .claudeInstaller, installed: try version("2.1.281")),
            running: [])
        #expect(update.latest == .unknown)
        #expect(update.method == .claudeInstaller)
        #expect(update.program == "/Users/me/.local/bin/claude")
    }
}
