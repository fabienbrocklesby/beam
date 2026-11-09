import Foundation

/// How an agent CLI was installed, which says how to update it and where to
/// ask for its latest version.
public enum InstallMethod: Equatable, Sendable {
    case homebrewCask(token: String)
    case homebrewFormula(name: String)
    /// An npm package installed through mise's npm backend.
    case mise(package: String)
    /// A global npm package.
    case npm(package: String)
    case uv(tool: String)
    /// Claude Code's own installer, which keeps every version in one folder
    /// and updates through `claude update`.
    case claudeInstaller

    /// Tells the method from where the program really lives, with its
    /// symlinks resolved. Nil for anything Beam does not know how to update,
    /// such as bun's and pnpm's global folders: npm would install a second
    /// copy rather than update theirs.
    public init?(resolvedPath: String) {
        let parts = resolvedPath.split(separator: "/").map(String.init)
        /// What follows the first place `run` appears in the path.
        func after(_ run: String...) -> ArraySlice<String>? {
            guard parts.count >= run.count else { return nil }
            for start in 0...(parts.count - run.count) where Array(parts[start..<start + run.count]) == run {
                return parts[(start + run.count)...]
            }
            return nil
        }
        let package = after("lib", "node_modules").flatMap(Self.package)

        // Caskroom/<token>/<version>/<program>, and the same for a Cellar.
        // A formula built from an npm package keeps it inside the Cellar.
        if let rest = after("Caskroom"), rest.count >= 3, let token = rest.first {
            self = .homebrewCask(token: token)
        } else if let rest = after("Cellar"), rest.count >= 3, let name = rest.first {
            self = .homebrewFormula(name: name)
        } else if let tool = after("mise", "installs")?.first, tool.hasPrefix("npm-"), let package {
            self = .mise(package: package)
        } else if let package {
            // Also what mise's own Node installs globally.
            self = .npm(package: package)
        } else if let rest = after("uv", "tools"), rest.count >= 2, let tool = rest.first {
            self = .uv(tool: tool)
        } else if after(".local", "share", "claude", "versions")?.isEmpty == false {
            self = .claudeInstaller
        } else {
            return nil
        }
    }

    /// The package a path inside `node_modules` belongs to, as far as the
    /// path goes past it.
    private static func package(in rest: ArraySlice<String>) -> String? {
        guard let first = rest.first else { return nil }
        guard first.hasPrefix("@") else { return rest.count >= 2 ? first : nil }
        guard rest.count >= 3 else { return nil }
        return first + "/" + rest[rest.index(after: rest.startIndex)]
    }

    /// For the menu, as in "installed with Homebrew".
    public var name: String {
        switch self {
        case .homebrewCask, .homebrewFormula: "Homebrew"
        case .mise: "mise"
        case .npm: "npm"
        case .uv: "uv"
        case .claudeInstaller: "Claude's installer"
        }
    }

    /// What a shell runs to update the agent. `program` is where the shell
    /// finds it, which Claude's installer is updated through: typed as
    /// `claude update`, Beam would take it for Claude itself, give it hooks
    /// and resume it as a conversation on the next launch.
    public func updateCommand(program: String) -> String {
        switch self {
        case .homebrewCask(let token): "brew upgrade --cask \(Shell.escape(token))"
        case .homebrewFormula(let name): "brew upgrade \(Shell.escape(name))"
        case .mise(let package): "mise upgrade \(Shell.escape("npm:" + package))"
        case .npm(let package): "npm install -g \(Shell.escape(package + "@latest"))"
        case .uv(let tool): "uv tool upgrade \(Shell.escape(tool))"
        case .claudeInstaller: "\(Shell.escape(program)) update"
        }
    }

    /// Where the latest version is published. Homebrew's own cache can be
    /// days behind; `brew upgrade` refreshes it first, so its API is what an
    /// update installs.
    public var latestSource: URL? {
        switch self {
        case .homebrewCask(let token): Self.url("https://formulae.brew.sh/api/cask/", token, ".json")
        case .homebrewFormula(let name): Self.url("https://formulae.brew.sh/api/formula/", name, ".json")
        case .mise(let package), .npm(let package): Self.url("https://registry.npmjs.org/", package, "/latest")
        case .uv(let tool): Self.url("https://pypi.org/pypi/", tool, "/json")
        case .claudeInstaller: Self.url("https://registry.npmjs.org/", "@anthropic-ai/claude-code", "/latest")
        }
    }

    private static func url(_ base: String, _ name: String, _ suffix: String) -> URL? {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: base + $0 + suffix) }
    }

    /// The version in what `latestSource` answered.
    public func latestVersion(from answer: Data) -> Version? {
        let decoder = JSONDecoder()
        let version: String?
        switch self {
        case .homebrewCask, .mise, .npm, .claudeInstaller:
            version = (try? decoder.decode(Versioned.self, from: answer))?.version
        case .homebrewFormula:
            version = (try? decoder.decode(Formula.self, from: answer))?.versions.stable
        case .uv:
            version = (try? decoder.decode(Project.self, from: answer))?.info.version
        }
        return version.flatMap(Version.init(in:))
    }

    /// A cask, or an npm package's latest manifest.
    private struct Versioned: Decodable {
        let version: String
    }

    private struct Formula: Decodable {
        struct Versions: Decodable {
            let stable: String
        }
        let versions: Versions
    }

    /// A PyPI project.
    private struct Project: Decodable {
        struct Info: Decodable {
            let version: String
        }
        let info: Info
    }
}
