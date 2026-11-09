import Foundation

/// What beam-attach sends as it connects: the pane it serves, its window size,
/// and the working directory and environment a new session starts with. A
/// session that already exists ignores the last two.
///
/// The payload is the `WindowSize`, then NUL-terminated strings: the pane ID,
/// the working directory, then one `KEY=value` per environment variable.
public struct AttachRequest: Equatable, Sendable {
    public enum Failure: Error, Equatable {
        case malformed
    }

    public var pane: Pane.ID
    public var size: WindowSize
    /// Empty when beam-attach's own working directory has gone.
    public var workingDirectory: String
    public var environment: [String]

    public init(pane: Pane.ID, size: WindowSize, workingDirectory: String, environment: [String]) {
        self.pane = pane
        self.size = size
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    public init(payload: [UInt8]) throws(Failure) {
        guard payload.count >= WindowSize.byteCount, payload.last == 0 else { throw .malformed }
        guard let size = try? WindowSize(bytes: payload[..<WindowSize.byteCount]) else { throw .malformed }
        let strings = payload[WindowSize.byteCount...].dropLast()
            .split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard strings.count >= 2, let uuid = UUID(uuidString: strings[0]) else { throw .malformed }
        self.init(
            pane: Pane.ID(uuid: uuid), size: size, workingDirectory: strings[1],
            environment: Array(strings[2...]))
    }

    public var payload: [UInt8] {
        size.bytes + ([pane.description, workingDirectory] + environment).flatMap { Array($0.utf8) + [0] }
    }
}
