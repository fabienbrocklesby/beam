import BeamCore
import Darwin
import Foundation
import os

/// Beam's control connection to beamd, which runs every pane's session
/// (docs/sessions.md). Starts beamd when none is running.
final class DaemonClient {
    /// beamd's socket, which each pane's beam-attach and agent hooks reach
    /// through `BEAM_SOCKET`.
    let path: String
    /// What each pane's terminal runs: beam-attach. libghostty always runs a
    /// surface's command through `bash -c "exec -l <command>"`, so it is a
    /// shell word, and no shell stays behind.
    let surfaceCommand: String
    /// Added to every pane's environment: where beamd is, and the shell
    /// integration Ghostty would have added to the shell itself.
    let paneEnvironment: [String: String]
    /// Every event beamd sends, in order.
    var onEvent: ((ControlEvent) -> Void)?
    /// Once, when beamd goes away or breaks the protocol.
    var onClose: (() -> Void)?
    private(set) var isConnected = true

    private let descriptor: WatchedDescriptor
    private let source: any DispatchSourceRead
    private let writer: Writer
    private var reader = DaemonFrameReader()
    /// Reaps the beamd this Beam started, should it exit first.
    private var started: (any DispatchSourceProcess)?

    /// Connects to beamd at `$TMPDIR/beamd-<version>.sock`, starting the
    /// bundled one when nothing answers, and asks for its sessions. Nil when
    /// neither works, and then panes run their shell themselves.
    init?(bundle: Bundle) {
        let helpers = bundle.bundleURL.appending(path: "Contents/Helpers")
        let beamd = helpers.appending(path: "beamd").path
        let attach = helpers.appending(path: "beam-attach").path
        guard FileManager.default.isExecutableFile(atPath: beamd), FileManager.default.isExecutableFile(atPath: attach)
        else {
            Logger.app.error(
                "no beamd or beam-attach in \(helpers.path, privacy: .public), so panes will not survive quit")
            return nil
        }
        let path = DaemonSocket.path(in: DaemonSocket.directory())
        let socket: Int32
        var process: pid_t?
        do {
            if let running = try? DaemonSocket.connect(to: path) {
                socket = running
            } else {
                let listener = try DaemonSocket.listen(at: path)
                defer { Darwin.close(listener) }
                process = try Self.start(beamd, listener: listener)
                // Queued until beamd accepts it, so there is no start to wait for.
                socket = try DaemonSocket.connect(to: path)
            }
        } catch {
            Logger.app.error("could not reach beamd at \(path, privacy: .public): \(error, privacy: .public)")
            return nil
        }
        self.path = path
        _ = fcntl(socket, F_SETFL, O_NONBLOCK)
        descriptor = WatchedDescriptor(socket)
        surfaceCommand = Shell.escape(attach)
        paneEnvironment = ["BEAM_SOCKET": path].merging(Self.shellIntegration(bundle: bundle)) { $1 }
        writer = Writer(descriptor: descriptor)
        source = descriptor.makeReadSource()
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
        source.resume()
        if let process { reap(process) }
        // The first frame makes this the control connection. A connection
        // that closes without one would let an idle beamd exit.
        send(.list)
    }

    isolated deinit {
        writer.cancel()
        source.cancel()
        started?.cancel()
    }

    func send(_ request: ControlRequest) {
        guard isConnected else { return }
        do {
            writer.write(try DaemonFrame(.control, encoding: request).bytes)
        } catch {
            Logger.app.error("could not encode a request for beamd: \(error, privacy: .public)")
        }
        if writer.failed { close() }
    }

    private func read() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(descriptor.value, &buffer, buffer.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        guard count > 0 else { return close() }
        reader.append(buffer[..<count])
        do {
            while isConnected, let frame = try reader.next() {
                guard frame.kind == .control else { throw DaemonFrameReader.Failure.unknownKind(frame.kind.rawValue) }
                onEvent?(try frame.decode(ControlEvent.self))
            }
        } catch {
            Logger.app.error("closing beamd's connection, which sent \(String(describing: error), privacy: .public)")
            close()
        }
    }

    private func close() {
        guard isConnected else { return }
        isConnected = false
        writer.cancel()
        source.cancel()
        Logger.app.error("beamd went away, so new panes will not survive quit")
        let onClose = self.onClose
        self.onClose = nil
        onClose?()
    }

    private func reap(_ process: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: process, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                var status: Int32 = 0
                waitpid(process, &status, 0)
                self?.started?.cancel()
                self?.started = nil
            }
        }
        source.resume()
        started = source
    }

    /// Starts beamd in a session of its own, so it outlives Beam and no
    /// terminal's hangup reaches it, with `listener` as descriptor 3 and
    /// nothing else of Beam's.
    private static func start(_ beamd: String, listener: Int32) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for (descriptor, flags) in [(0, O_RDONLY), (1, O_WRONLY), (2, O_WRONLY)] {
            posix_spawn_file_actions_addopen(&actions, Int32(descriptor), "/dev/null", flags, 0)
        }
        if listener == 3 {
            posix_spawn_file_actions_addinherit_np(&actions, 3)
        } else {
            posix_spawn_file_actions_adddup2(&actions, listener, 3)
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        var signals = sigset_t()
        sigemptyset(&signals)
        posix_spawnattr_setsigmask(&attributes, &signals)
        sigfillset(&signals)
        posix_spawnattr_setsigdefault(&attributes, &signals)

        var process: pid_t = 0
        let argv = [strdup(beamd), nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0)=\($1)") } + [nil]
        defer { for pointer in argv + environment { free(pointer) } }
        let result = posix_spawn(&process, beamd, &actions, &attributes, argv, environment)
        guard result == 0 else { throw DaemonSocket.Failure.system("posix_spawn", result) }
        Logger.app.info("started beamd, pid \(process)")
        return process
    }

    /// For the user's login shell, which `login` gives every pane whatever
    /// `$SHELL` Beam inherited, and only when the bundle has the integration.
    private static func shellIntegration(bundle: Bundle) -> [String: String] {
        guard let resources = bundle.resourceURL else { return [:] }
        let directory = resources.appending(path: "ghostty/shell-integration/zsh").path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue,
            let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell
        else { return [:] }
        return PaneEnvironment.shellIntegration(
            shell: String(cString: shell), zdotdir: ProcessInfo.processInfo.environment["ZDOTDIR"],
            directory: directory)
    }
}
