import Foundation

/// A program's version as its `--version` or a package registry gives it:
/// dotted numbers and maybe a pre-release tag, ordered the way semantic
/// versions are.
public struct Version: Comparable, Sendable, CustomStringConvertible {
    private let numbers: [Int]
    /// The tag's dot-separated identifiers, empty for a release.
    private let prerelease: [String]

    /// The first version in `text`, such as "2.1.281 (Claude Code)" or
    /// "codex-cli 0.166.0". It needs a dot, so a lone number is not taken for
    /// one. What follows the numbers without a hyphen, like a Homebrew
    /// revision ("_1") or a cask's build (",8812"), is left off.
    public init?(in text: String) {
        guard let match = text.firstMatch(of: #/(\d+(?:\.\d+)+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?/#) else {
            return nil
        }
        let numbers = match.1.split(separator: ".").compactMap { Int($0) }
        // A number too long for an Int.
        guard numbers.count == match.1.split(separator: ".").count else { return nil }
        self.numbers = numbers
        prerelease = match.2.map { $0.split(separator: ".").map(String.init) } ?? []
    }

    public var description: String {
        let release = numbers.map(String.init).joined(separator: ".")
        return prerelease.isEmpty ? release : release + "-" + prerelease.joined(separator: ".")
    }

    /// Missing numbers count as zero, so 1.2 is 1.2.0.
    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        // A pre-release comes before its release.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, _): return false
        case (false, true): return true
        case (false, false): return precedes(lhs.prerelease, rhs.prerelease)
        }
    }

    /// Semantic versioning's order for pre-release tags: identifier by
    /// identifier, numbers by value and before words, and a tag before any
    /// longer one it starts.
    private static func precedes(_ lhs: [String], _ rhs: [String]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            switch (Int(left), Int(right)) {
            case (let left?, let right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.count < rhs.count
    }

    /// Runs `program --version` and reads the version it prints. Nil when
    /// it fails, prints none, or is still going after `timeout` seconds and
    /// is killed.
    ///
    /// Blocks until the program exits, so call it off the main thread.
    public static func reported(
        by program: String, environment: [String: String], timeout: TimeInterval
    ) -> Version? {
        // The output goes to a file rather than a pipe: some npm packages
        // start an update check in the background that inherits it and
        // would hold a pipe open long after the program has gone.
        let output = FileManager.default.temporaryDirectory.appending(path: "beam-version-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
            let handle = try? FileHandle(forWritingTo: output)
        else { return nil }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }

        let process = Process()
        process.executableURL = URL(filePath: program)
        process.arguments = ["--version"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        guard process.runAndWait(timeout: timeout), process.terminationStatus == 0,
            let text = try? String(contentsOf: output, encoding: .utf8)
        else { return nil }
        return Version(in: text)
    }
}
