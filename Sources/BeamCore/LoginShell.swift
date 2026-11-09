import Foundation

/// The user's own shell, asked for the `PATH` it builds. That is where a
/// command typed into a pane is found; Beam's own `PATH` is launchd's bare
/// one when it starts from Finder or the Dock.
public enum LoginShell {
    /// Runs `shell` as an interactive login shell, as a pane's shell runs,
    /// and returns the `PATH` it ends up with. Interactive matters: rc files
    /// such as `.zshrc` often add to `PATH` and only run for interactive
    /// shells. Nil when the shell fails, or is still going after `timeout`
    /// seconds and is killed.
    ///
    /// Blocks until the shell exits, so call it off the main thread.
    public static func path(shell: String, environment: [String: String], timeout: TimeInterval) -> String? {
        // The PATH comes back through a file rather than a pipe: rc files
        // can start background processes that inherit stdout and would hold
        // a pipe open long after the shell has gone.
        let output = FileManager.default.temporaryDirectory.appending(path: "beam-path-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-l", "-i", "-c", #"printf '%s' "$PATH" > "$BEAM_PATH_OUTPUT""#]
        process.environment = environment.merging(["BEAM_PATH_OUTPUT": output.path]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Fails too when an rc file is stuck, say on a prompt or a network
        // mount.
        guard process.runAndWait(timeout: timeout) else { return nil }
        guard let path = try? String(contentsOf: output, encoding: .utf8), !path.isEmpty else { return nil }
        return path
    }
}
