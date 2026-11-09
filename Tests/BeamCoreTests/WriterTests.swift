import BeamCore
import Darwin
import Testing

/// Over a socket pair whose far end is read off the main thread, while the
/// writer's source runs on the main queue.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WriterTests {
    private func pair() throws -> (near: Int32, far: Int32) {
        var descriptors: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(descriptors[0], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return (descriptors[0], descriptors[1])
    }

    /// Far more than the socket buffer holds, so most of it waits.
    @Test func everythingWrittenArrivesInOrderAndThenItDrains() async throws {
        let (near, far) = try pair()
        defer {
            close(near)
            close(far)
        }
        let sent = (0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        let reader = Task.detached { () -> [UInt8] in
            var received: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 65536)
            while received.count < sent.count {
                let count = read(far, &buffer, buffer.count)
                guard count > 0 else { break }
                received += buffer[..<count]
            }
            return received
        }
        let writer = Writer(descriptor: near)
        let (drained, drain) = AsyncStream.makeStream(of: Void.self)
        writer.onDrain = { drain.yield() }
        writer.write(Array(sent[..<1000]))
        writer.write(Array(sent[1000...]))
        #expect(writer.pendingCount > 0)
        #expect(await reader.value == sent)
        var drains = drained.makeAsyncIterator()
        while writer.pendingCount > 0 { _ = await drains.next() }
        #expect(!writer.failed)
        writer.cancel()
    }

    @Test func aPeerThatHasGoneFailsTheWriter() throws {
        let (near, far) = try pair()
        defer { close(near) }
        close(far)
        let writer = Writer(descriptor: near)
        writer.write([1, 2, 3])
        #expect(writer.failed)
        #expect(writer.pendingCount == 0)
        writer.write([4])
        #expect(writer.pendingCount == 0)
        writer.cancel()
    }
}
