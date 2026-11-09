import Darwin
import Foundation

/// beamd's socket, which Beam, beam-attach and agent hooks connect to.
public enum DaemonSocket {
    public enum Failure: Error, Equatable {
        /// Longer than a socket address holds.
        case pathTooLong
        /// A system call failed with `errno`.
        case system(String, Int32)
    }

    /// Changes whenever the protocol does, so a newer Beam starts a beamd of
    /// its own rather than talking to an older one.
    public static let protocolVersion = 1

    /// The user's private temporary folder: `$TMPDIR`, which a launch can
    /// point elsewhere to get a beamd of its own (make bench does), else the
    /// one macOS gives the user. Foundation's own ignores `$TMPDIR`.
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        guard let path = environment["TMPDIR"], !path.isEmpty else { return FileManager.default.temporaryDirectory }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// In `directory`, the user's private temporary folder. The name stays
    /// the same from launch to launch: sessions outlive the Beam that started
    /// them.
    public static func path(in directory: URL) -> String {
        directory.appending(path: "beamd-\(protocolVersion).sock").path
    }

    /// A non-blocking socket listening at `path`, for this user only, that
    /// processes beamd starts do not inherit. Replaces whatever is at `path`,
    /// so the caller first makes sure no beamd answers there.
    public static func listen(at path: String) throws -> Int32 {
        var address = try address(path)
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw Failure.system("socket", errno) }
        _ = fcntl(socket, F_SETFD, FD_CLOEXEC)
        _ = fcntl(socket, F_SETFL, O_NONBLOCK)
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(socket, SOMAXCONN) == 0 else {
            let error = errno
            close(socket)
            unlink(path)
            throw Failure.system("listen", error)
        }
        return socket
    }

    /// A blocking socket connected to `path`, that processes the caller
    /// starts do not inherit and that never raises SIGPIPE.
    public static func connect(to path: String) throws -> Int32 {
        var address = try address(path)
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw Failure.system("socket", errno) }
        _ = fcntl(socket, F_SETFD, FD_CLOEXEC)
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let error = errno
            close(socket)
            throw Failure.system("connect", error)
        }
        return socket
    }

    /// Opens a connection to `path`, writes `frame` and closes. Blocks until
    /// it is written, so only for a short-lived process such as `beam hook`.
    public static func send(_ frame: DaemonFrame, to path: String) throws {
        let socket = try connect(to: path)
        defer { close(socket) }
        let bytes = frame.bytes
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes {
                write(socket, $0.baseAddress?.advanced(by: offset), $0.count - offset)
            }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw Failure.system("write", errno) }
            offset += written
        }
    }

    /// Whether `descriptor` is a socket bound to `path`, as the listener Beam
    /// hands beamd is; a client's socket is bound to nothing. macOS has no
    /// SO_ACCEPTCONN to ask whether a socket listens.
    public static func isBound(_ descriptor: Int32, to path: String) -> Bool {
        var address = sockaddr_un()
        var length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0, address.sun_family == sa_family_t(AF_UNIX) else { return false }
        let bound = withUnsafeBytes(of: address.sun_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return bound == path
    }

    /// The socket address for `path`.
    static func address(_ path: String) throws(Failure) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw .pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { sunPath in
            bytes.withUnsafeBytes { sunPath.copyBytes(from: $0) }
        }
        return address
    }
}
