import BeamCore
import Darwin
import Foundation
import os

// beamd: owns the pty of every Beam pane, so shells and agents outlive Beam.
// See docs/sessions.md.

// A pane that goes away mid-write is an error to handle, not a signal that
// ends every session.
signal(SIGPIPE, SIG_IGN)

let path = DaemonSocket.path(in: DaemonSocket.directory())

/// Beam binds the socket before it starts beamd and hands it over as
/// descriptor 3, so its first connection waits in the socket's queue instead
/// of racing beamd's start. Listening again only fails if descriptor 3 is a
/// connection rather than the listener.
func inheritedListener() -> Int32? {
    guard DaemonSocket.isBound(3, to: path), listen(3, SOMAXCONN) == 0 else { return nil }
    _ = fcntl(3, F_SETFD, FD_CLOEXEC)
    _ = fcntl(3, F_SETFL, O_NONBLOCK)
    return 3
}

/// Started any other way, beamd binds the socket itself, unless a beamd
/// already answers there.
func boundListener() -> Int32 {
    if let running = try? DaemonSocket.connect(to: path) {
        close(running)
        Logger.daemon.info("another beamd is serving \(path, privacy: .public)")
        exit(EXIT_SUCCESS)
    }
    do {
        return try DaemonSocket.listen(at: path)
    } catch {
        Logger.daemon.fault(
            "could not listen at \(path, privacy: .public): \(String(describing: error), privacy: .public)")
        exit(EXIT_FAILURE)
    }
}

let daemon = Daemon(listener: inheritedListener() ?? boundListener(), path: path)
Logger.daemon.info("serving \(path, privacy: .public)")
// Every handler runs on the main actor, so the main queue has to be drained
// on the main thread. dispatchMain() would exit that thread and leave the
// queue to a worker.
CFRunLoopRun()
