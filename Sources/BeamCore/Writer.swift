import Darwin
import Dispatch

/// Writes to a non-blocking descriptor without ever blocking: what the
/// descriptor will not take yet waits, in order, and goes as it drains. Runs
/// on the main queue, as beamd and Beam both do.
@MainActor
public final class Writer {
    private let descriptor: Int32
    private var pending: [UInt8] = []
    private let source: any DispatchSourceWrite
    private var waiting = false
    /// Set once a write fails; everything after it is dropped.
    public private(set) var failed = false
    /// Runs each time everything pending has been written.
    public var onDrain: (() -> Void)?

    public init(descriptor: Int32) {
        self.descriptor = descriptor
        source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    isolated deinit {
        cancel()
    }

    /// Bytes accepted but not written yet.
    public var pendingCount: Int { pending.count }

    public func write(_ bytes: [UInt8]) {
        guard !failed, !bytes.isEmpty else { return }
        pending += bytes
        if !waiting { flush() }
    }

    /// Stops writing. Does not close the descriptor, which its owner does.
    public func cancel() {
        if !waiting { source.resume() }
        waiting = true
        source.cancel()
    }

    private func flush() {
        while !pending.isEmpty {
            let written = pending.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                pending.removeFirst(written)
            } else if written < 0, errno == EAGAIN {
                if !waiting {
                    waiting = true
                    source.resume()
                }
                return
            } else if written < 0, errno == EINTR {
                continue
            } else {
                failed = true
                pending = []
                break
            }
        }
        if waiting, !source.isCancelled {
            waiting = false
            source.suspend()
        }
        onDrain?()
    }
}
