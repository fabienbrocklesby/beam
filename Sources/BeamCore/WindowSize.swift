/// A terminal's size in cells and pixels, as `TIOCGWINSZ` reports it. On the
/// wire it is four little-endian `UInt16`s: columns, rows, width, height.
public struct WindowSize: Equatable, Sendable {
    public enum Failure: Error, Equatable {
        case malformed
    }

    public static let byteCount = 8

    public var columns: UInt16
    public var rows: UInt16
    public var width: UInt16
    public var height: UInt16

    public init(columns: UInt16, rows: UInt16, width: UInt16, height: UInt16) {
        self.columns = columns
        self.rows = rows
        self.width = width
        self.height = height
    }

    public init(bytes: some Collection<UInt8>) throws(Failure) {
        guard bytes.count == Self.byteCount else { throw .malformed }
        let values = stride(from: 0, to: Self.byteCount, by: 2).map { offset in
            let low = bytes[bytes.index(bytes.startIndex, offsetBy: offset)]
            let high = bytes[bytes.index(bytes.startIndex, offsetBy: offset + 1)]
            return UInt16(low) | UInt16(high) << 8
        }
        self.init(columns: values[0], rows: values[1], width: values[2], height: values[3])
    }

    public var bytes: [UInt8] {
        [columns, rows, width, height].flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }
}
