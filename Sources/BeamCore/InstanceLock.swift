import Foundation

/// One Beam's claim on the folder its beamd serves from, held until the
/// process ends, so a second Beam started there can stand down.
///
/// Two Beams on one beamd fight: the newer takes beamd's control connection,
/// which leaves the older without agent reports, and ends the sessions its
/// own state file does not name. The claim is an exclusive `flock` on a file
/// in the folder, which the kernel drops however the process ends.
public final class InstanceLock: Equatable, Sendable {
    public enum Claim: Equatable, Sendable {
        /// The folder is this process's for as long as it keeps the lock.
        case made(InstanceLock)
        /// Another process holds it. Its ID is nil in the moment before it
        /// has written it.
        case taken(by: pid_t?)
        /// The folder would not hold a lock file.
        case unavailable
    }

    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    public static func == (lhs: InstanceLock, rhs: InstanceLock) -> Bool { lhs === rhs }

    /// In `directory`, where beamd's socket is, and named for the protocol as
    /// the socket is: the Beams that would share a beamd share a lock.
    public static func path(in directory: URL) -> String {
        directory.appending(path: "beam-\(DaemonSocket.protocolVersion).lock").path
    }

    /// Claims `directory` for `process`, or says who holds it.
    public static func claim(in directory: URL, process: pid_t = getpid()) -> Claim {
        // Closed in every program this one starts: beamd outlives Beam, and
        // would keep the claim with it.
        let descriptor = open(path(in: directory), O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return .unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let isHeld = errno == EWOULDBLOCK
            defer { close(descriptor) }
            return isHeld ? .taken(by: holder(in: descriptor)) : .unavailable
        }
        // The claim stands even if its holder cannot be written down.
        let text = Array("\(process)\n".utf8)
        if ftruncate(descriptor, 0) == 0 { _ = pwrite(descriptor, text, text.count, 0) }
        return .made(InstanceLock(descriptor: descriptor))
    }

    private static func holder(in descriptor: Int32) -> pid_t? {
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = pread(descriptor, &bytes, bytes.count, 0)
        guard count > 0 else { return nil }
        return pid_t(String(decoding: bytes[..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
