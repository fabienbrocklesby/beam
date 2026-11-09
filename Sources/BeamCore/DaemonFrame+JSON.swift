import Foundation

// The `control` and `report` kinds carry one message each, as JSON.
extension DaemonFrame {
    public init(_ kind: Kind, encoding message: some Encodable) throws {
        self.init(kind, payload: Array(try JSONEncoder().encode(message)))
    }

    public func decode<Message: Decodable>(_ type: Message.Type) throws -> Message {
        try JSONDecoder().decode(type, from: Data(payload))
    }
}
