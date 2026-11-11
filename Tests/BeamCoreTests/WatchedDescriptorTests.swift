import BeamCore
import Darwin
import Dispatch
import Testing

/// Over socket pairs, with every source on the main queue as beamd and Beam
/// run them. Neither far end is read, so a write source with output pending
/// stays armed and quiet, as one is when its peer stops reading.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WatchedDescriptorTests {
    private func pair() throws -> (near: Int32, far: Int32) {
        var descriptors: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        _ = fcntl(descriptors[0], F_SETFL, O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(descriptors[0], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return (descriptors[0], descriptors[1])
    }

    /// Every descriptor closed, in order. Closes for real, so nothing leaks.
    private func closes() -> (AsyncStream<Int32>, (Int32) -> Void) {
        let (closed, continuation) = AsyncStream.makeStream(of: Int32.self)
        return (
            closed,
            { descriptor in
                _ = close(descriptor)
                continuation.yield(descriptor)
            }
        )
    }

    /// A read source on a quiet descriptor of its own. Cancelled after other
    /// sources, its descriptor closes after their cancel handlers have run:
    /// cancellation goes through libdispatch in order.
    private func probe(closingWith close: @escaping (Int32) -> Void) throws -> (Int32, any DispatchSourceRead) {
        let (near, far) = try pair()
        _ = Darwin.close(far)
        let source = WatchedDescriptor(near, close: close).makeReadSource()
        source.setEventHandler {}
        source.resume()
        return (near, source)
    }

    @Test func staysOpenWhileASourceOnItIsNotCancelled() async throws {
        let (near, far) = try pair()
        defer { close(far) }
        let (closed, record) = closes()
        var closedNext = closed.makeAsyncIterator()
        let watched = WatchedDescriptor(near, close: record)
        let read = watched.makeReadSource()
        let write = watched.makeWriteSource()
        var filler = [UInt8](repeating: 0, count: 65536)
        while Darwin.write(near, &filler, filler.count) > 0 {}
        for source in [read, write] as [any DispatchSourceProtocol] {
            source.setEventHandler {}
            source.resume()
        }
        let (probed, probe) = try probe(closingWith: record)

        read.cancel()
        probe.cancel()
        let first = await closedNext.next()
        #expect(first == probed)
        write.cancel()
        let second = await closedNext.next()
        #expect(second == near)
    }

    /// As beamd closed a connection whose peer had stopped reading: the
    /// Writer's source armed, and both sources cancelled at once.
    @Test func aWriterWithOutputPendingAndAReadSourceCloseItOnce() async throws {
        let (near, far) = try pair()
        defer { close(far) }
        let (closed, record) = closes()
        var closedNext = closed.makeAsyncIterator()
        let watched = WatchedDescriptor(near, close: record)
        let writer = Writer(descriptor: watched)
        let read = watched.makeReadSource()
        read.setEventHandler {}
        read.resume()
        writer.write([UInt8](repeating: 7, count: 1 << 20))
        #expect(writer.pendingCount > 0)
        let (probed, probe) = try probe(closingWith: record)

        writer.cancel()
        read.cancel()
        probe.cancel()
        let first = await closedNext.next()
        #expect(first == near)
        let second = await closedNext.next()
        #expect(second == probed)
    }
}
