/// One unit of beamd's protocol, written as the kind byte, the payload's length
/// as a little-endian `UInt32`, then the payload. beam-attach writes the same
/// bytes from C, so the layout and the kind numbers never change within a
/// protocol version (`docs/sessions.md`).
/// A connection's first frame says what it is for.
public struct DaemonFrame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        /// Opens a connection from beam-attach. The payload is an
        /// `AttachRequest`.
        case attach = 1
        /// Bytes typed into an attached pane.
        case input = 2
        /// An attached pane's new `WindowSize`.
        case resize = 3
        /// Opens Beam's connection, and carries every message on it after:
        /// a `ControlRequest` from Beam or a `ControlEvent` from beamd, as
        /// JSON.
        case control = 4
        /// One `AgentReport` from `beam hook`, as JSON. The connection
        /// closes after it.
        case report = 5
    }

    public static let headerSize = 5
    /// Far above any real frame: input arrives a read at a time, and an attach
    /// request is mostly its environment.
    public static let maximumPayload = 1 << 20

    public var kind: Kind
    public var payload: [UInt8]

    public init(_ kind: Kind, payload: [UInt8] = []) {
        self.kind = kind
        self.payload = payload
    }

    public var bytes: [UInt8] {
        let length = UInt32(payload.count).littleEndian
        return [kind.rawValue] + withUnsafeBytes(of: length, Array.init) + payload
    }
}
