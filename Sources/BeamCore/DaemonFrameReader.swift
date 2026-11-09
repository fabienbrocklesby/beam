/// Cuts a byte stream into `DaemonFrame`s, however reads happened to split it.
public struct DaemonFrameReader: Sendable {
    public enum Failure: Error, Equatable {
        case unknownKind(UInt8)
        /// The header announced a payload over `DaemonFrame.maximumPayload`.
        case tooLong(Int)
    }

    private var buffer: [UInt8] = []
    /// Where the next frame starts in `buffer`. Consumed bytes are dropped in
    /// bulk, so a stream of small frames does not copy the buffer per frame.
    private var start = 0

    public init() {}

    public mutating func append(_ bytes: some Sequence<UInt8>) {
        if start > 0, start * 2 >= buffer.count {
            buffer.removeFirst(start)
            start = 0
        }
        buffer.append(contentsOf: bytes)
    }

    /// The next whole frame, or nil until more bytes arrive. After a failure
    /// the stream cannot be trusted, and the connection should close.
    public mutating func next() throws(Failure) -> DaemonFrame? {
        guard buffer.count - start >= DaemonFrame.headerSize else { return nil }
        guard let kind = DaemonFrame.Kind(rawValue: buffer[start]) else { throw .unknownKind(buffer[start]) }
        let length = (1...4).reduce(0) { $0 | Int(buffer[start + $1]) << (8 * ($1 - 1)) }
        guard length <= DaemonFrame.maximumPayload else { throw .tooLong(length) }
        let payloadStart = start + DaemonFrame.headerSize
        guard buffer.count - payloadStart >= length else { return nil }
        start = payloadStart + length
        return DaemonFrame(kind, payload: Array(buffer[payloadStart..<start]))
    }
}
