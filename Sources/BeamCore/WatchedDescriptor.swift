import Darwin
import Dispatch

/// A descriptor that dispatch sources watch, closed once every source made
/// from it has been cancelled and its cancel handler has run. Closing it any
/// sooner races libdispatch (`man dispatch_source_create`), which reports the
/// source's resource as vanished and can crash doing so. Its sources run on
/// the main queue, as beamd and Beam both do.
@MainActor
public final class WatchedDescriptor {
    public let value: Int32
    private let close: (Int32) -> Void
    /// Sources made from this whose cancel handler has not run yet.
    private var watching = 0

    /// Takes ownership of `value`. `close` closes it, and is there for tests.
    public init(_ value: Int32, close: @escaping (Int32) -> Void = { _ = Darwin.close($0) }) {
        self.value = value
        self.close = close
    }

    /// Its cancel handler is the descriptor's: do not set another.
    public func makeReadSource() -> any DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: value, queue: .main)
        watch(source)
        return source
    }

    /// Its cancel handler is the descriptor's: do not set another.
    public func makeWriteSource() -> any DispatchSourceWrite {
        let source = DispatchSource.makeWriteSource(fileDescriptor: value, queue: .main)
        watch(source)
        return source
    }

    private func watch(_ source: any DispatchSourceProtocol) {
        watching += 1
        // Holds this until the last source has gone, however long its owner
        // lives. A cancel handler runs once, so the descriptor closes once.
        source.setCancelHandler {
            MainActor.assumeIsolated { self.sourceCancelled() }
        }
    }

    private func sourceCancelled() {
        watching -= 1
        if watching == 0 { close(value) }
    }
}
