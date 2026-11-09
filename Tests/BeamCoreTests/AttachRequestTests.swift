import BeamCore
import Foundation
import Testing

struct AttachRequestTests {
    let pane = Pane.ID()

    /// The payload as beam-attach builds it in C.
    private func payload(_ strings: [String], size: [UInt8] = [120, 0, 40, 0, 0xC0, 0x03, 0x80, 0x02]) -> [UInt8] {
        size + strings.flatMap { Array($0.utf8) + [0] }
    }

    @Test func readsWhatBeamAttachSends() throws {
        let request = try AttachRequest(
            payload: payload([pane.description, "/Users/me/project", "TERM=xterm-ghostty", "EMPTY="]))
        #expect(request.pane == pane)
        #expect(request.size == WindowSize(columns: 120, rows: 40, width: 960, height: 640))
        #expect(request.workingDirectory == "/Users/me/project")
        #expect(request.environment == ["TERM=xterm-ghostty", "EMPTY="])
    }

    @Test func roundTrips() throws {
        let request = AttachRequest(
            pane: pane, size: WindowSize(columns: 80, rows: 24, width: 640, height: 384),
            workingDirectory: "/tmp/a folder", environment: ["A=1", "JSON={\"x\": [1, 2]}"])
        #expect(try AttachRequest(payload: request.payload) == request)
    }

    @Test func anEmptyWorkingDirectoryIsKept() throws {
        // beam-attach sends an empty one when its own has gone.
        let request = try AttachRequest(payload: payload([pane.description, ""]))
        #expect(request.workingDirectory == "")
        #expect(request.environment.isEmpty)
    }

    @Test func malformedPayloadsAreRefused() {
        let cases: [[UInt8]] = [
            [120, 0, 40],
            payload(["not a uuid", "/tmp"]),
            payload([pane.description]),
            payload([pane.description, "/tmp", "UNTERMINATED"]).dropLast(),
        ]
        for bytes in cases {
            #expect(throws: AttachRequest.Failure.malformed) { try AttachRequest(payload: bytes) }
        }
    }

    @Test func aWindowSizeIsFourLittleEndianShorts() throws {
        let size = WindowSize(columns: 300, rows: 2, width: 1, height: 65535)
        #expect(size.bytes == [44, 1, 2, 0, 1, 0, 255, 255])
        #expect(try WindowSize(bytes: size.bytes) == size)
        #expect(throws: WindowSize.Failure.malformed) { try WindowSize(bytes: [1, 2, 3]) }
    }
}
