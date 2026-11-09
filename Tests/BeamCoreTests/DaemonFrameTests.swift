import BeamCore
import Testing

struct DaemonFrameTests {
    @Test func aFrameIsItsKindThenItsLittleEndianLengthThenItsPayload() {
        let frame = DaemonFrame(.input, payload: Array("ls\r".utf8))
        #expect(frame.bytes == [2, 3, 0, 0, 0] + Array("ls\r".utf8))
    }

    @Test func framesSurviveBeingSplitAcrossReadsAnywhere() throws {
        let frames = [
            DaemonFrame(.attach, payload: [1, 2, 3]),
            DaemonFrame(.input, payload: []),
            DaemonFrame(.resize, payload: Array(repeating: 7, count: 8)),
        ]
        let stream = frames.flatMap(\.bytes)
        for cut in 0...stream.count {
            var reader = DaemonFrameReader()
            var read: [DaemonFrame] = []
            reader.append(stream[..<cut])
            while let frame = try reader.next() { read.append(frame) }
            reader.append(stream[cut...])
            while let frame = try reader.next() { read.append(frame) }
            #expect(read == frames, "cut at \(cut)")
        }
    }

    @Test func anIncompleteFrameWaitsForTheRest() throws {
        var reader = DaemonFrameReader()
        reader.append(DaemonFrame(.input, payload: [1, 2, 3]).bytes.dropLast())
        #expect(try reader.next() == nil)
        reader.append([3])
        #expect(try reader.next() == DaemonFrame(.input, payload: [1, 2, 3]))
        #expect(try reader.next() == nil)
    }

    @Test func anUnknownKindIsRefused() {
        var reader = DaemonFrameReader()
        reader.append([99, 0, 0, 0, 0])
        #expect(throws: DaemonFrameReader.Failure.unknownKind(99)) { try reader.next() }
    }

    @Test func aPayloadPastTheLimitIsRefusedBeforeItArrives() {
        var reader = DaemonFrameReader()
        let length = UInt32(DaemonFrame.maximumPayload + 1)
        reader.append([2] + withUnsafeBytes(of: length.littleEndian, Array.init))
        #expect(throws: DaemonFrameReader.Failure.tooLong(Int(length))) { try reader.next() }
    }
}
