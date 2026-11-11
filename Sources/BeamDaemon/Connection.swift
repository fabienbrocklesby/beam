import BeamCore
import Darwin
import Dispatch
import os

/// One client of beamd's socket, read as `DaemonFrame`s and written as raw
/// bytes.
final class Connection {
    private let descriptor: WatchedDescriptor
    private let source: any DispatchSourceRead
    private let writer: Writer
    private var reader = DaemonFrameReader()
    private var reading = true
    private var closed = false
    /// Each frame, as it arrives.
    var onFrame: ((DaemonFrame) -> Void)?
    /// Once, when the peer goes away, breaks the protocol, or `close` is called.
    var onClose: (() -> Void)?

    init(descriptor: Int32) {
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        self.descriptor = WatchedDescriptor(descriptor)
        writer = Writer(descriptor: self.descriptor)
        source = self.descriptor.makeReadSource()
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
        source.resume()
    }

    isolated deinit {
        close()
    }

    /// Bytes sent but not yet taken by the peer.
    var pendingCount: Int { writer.pendingCount }

    /// Runs each time the peer has taken everything sent.
    var onDrain: (() -> Void)? {
        get { writer.onDrain }
        set { writer.onDrain = newValue }
    }

    func send(_ bytes: [UInt8]) {
        writer.write(bytes)
        if writer.failed { close() }
    }

    /// Stops reading until `resumeReading`, so the peer is held back.
    func suspendReading() {
        guard reading, !closed else { return }
        reading = false
        source.suspend()
    }

    func resumeReading() {
        guard !reading, !closed else { return }
        reading = true
        source.resume()
    }

    /// Closes once everything sent has been written, so the peer sees the
    /// last of a session's output before it sees the end.
    func closeAfterSending() {
        guard writer.pendingCount > 0, !writer.failed else {
            close()
            return
        }
        suspendReading()
        writer.onDrain = { [weak self] in self?.close() }
    }

    func close() {
        guard !closed else { return }
        closed = true
        writer.cancel()
        if !reading { source.resume() }
        source.cancel()
        onFrame = nil
        let onClose = self.onClose
        self.onClose = nil
        onClose?()
    }

    private func read() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(descriptor.value, &buffer, buffer.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        guard count > 0 else { return close() }
        reader.append(buffer[..<count])
        do {
            while !closed, let frame = try reader.next() { onFrame?(frame) }
        } catch {
            Logger.daemon.error("closing a connection that sent \(String(describing: error), privacy: .public)")
            close()
        }
    }
}
