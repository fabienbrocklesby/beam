import BeamCore
import Darwin
import Dispatch
import os

/// Accepts connections on beamd's socket and keeps every session, by pane,
/// with what its agent last reported.
final class Daemon {
    private let path: String
    private let listener: any DispatchSourceRead
    private var sessions: [Pane.ID: Session] = [:]
    /// Connections that have not yet said what they are for, by descriptor.
    private var connections: [Int32: Connection] = [:]
    /// Beam's control connection, while Beam runs.
    private var control: Connection?
    private var reports = AgentReports()

    /// Serves sessions on `listener`, a listening socket at `path`.
    init(listener socket: Int32, path: String) {
        self.path = path
        listener = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
        listener.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.accept(socket) }
        }
        listener.setCancelHandler { close(socket) }
        listener.resume()
    }

    private func accept(_ socket: Int32) {
        // One event may stand for several connections.
        while true {
            let descriptor = Darwin.accept(socket, nil, nil)
            guard descriptor >= 0 else { return }
            let connection = Connection(descriptor: descriptor)
            connections[descriptor] = connection
            connection.onFrame = { [weak self, weak connection] frame in
                guard let self, let connection else { return }
                open(connection, descriptor: descriptor, with: frame)
            }
            connection.onClose = { [weak self] in
                self?.connections[descriptor] = nil
                self?.exitIfIdle()
            }
        }
    }

    /// The first frame says what the connection is for.
    private func open(_ connection: Connection, descriptor: Int32, with frame: DaemonFrame) {
        connections[descriptor] = nil
        switch frame.kind {
        case .attach:
            attach(connection, with: frame)
        case .control:
            serve(connection, opening: frame)
        case .report:
            record(frame)
            connection.close()
        case .input, .resize:
            Logger.daemon.error(
                "closing a connection that opened with \(String(describing: frame.kind), privacy: .public)")
            connection.close()
        }
    }

    /// Attaches a pane to its session, starting the session if it has none.
    private func attach(_ connection: Connection, with frame: DaemonFrame) {
        guard let request = try? AttachRequest(payload: frame.payload) else {
            Logger.daemon.error("closing a connection that sent a malformed attach request")
            connection.close()
            return
        }
        let session: Session
        if let existing = sessions[request.pane] {
            session = existing
        } else {
            do {
                session = try Session(request)
            } catch {
                Logger.daemon.error(
                    "could not start a session for \(request.pane, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                connection.close()
                return
            }
            sessions[request.pane] = session
            session.onEnd = { [weak self] in
                self?.sessions[request.pane] = nil
                self?.reports.forget(request.pane)
                self?.exitIfIdle()
            }
        }
        session.attach(connection, size: request.size)
    }

    /// Takes `connection` as Beam's, answering its requests and passing on
    /// reports as they arrive. A newer Beam takes over from an older one.
    private func serve(_ connection: Connection, opening frame: DaemonFrame) {
        control?.close()
        control = connection
        connection.onFrame = { [weak self, weak connection] frame in
            guard let self, let connection else { return }
            receive(frame, from: connection)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, control === connection else { return }
            control = nil
            exitIfIdle()
        }
        receive(frame, from: connection)
    }

    private func receive(_ frame: DaemonFrame, from connection: Connection) {
        guard frame.kind == .control, let request = try? frame.decode(ControlRequest.self) else {
            Logger.daemon.error("closing a control connection that sent something else")
            connection.close()
            return
        }
        switch request {
        case .list:
            let live = sessions.keys.map { ControlEvent.Session(pane: $0, reports: reports.latest(for: $0)) }
            send(.sessions(live), to: connection)
        case .end(let pane):
            sessions[pane]?.hangUp()
        case .endAll:
            for session in sessions.values { session.hangUp() }
        }
    }

    /// Keeps a report from a live session's agent and passes it on to Beam.
    /// A report for any other pane comes from one that has gone.
    private func record(_ frame: DaemonFrame) {
        guard let report = try? frame.decode(AgentReport.self) else {
            Logger.daemon.error("dropping a report that is not one")
            return
        }
        guard sessions[report.pane] != nil else { return }
        reports.record(report)
        if let control { send(.report(report), to: control) }
    }

    private func send(_ event: ControlEvent, to connection: Connection) {
        do {
            connection.send(try DaemonFrame(.control, encoding: event).bytes)
        } catch {
            Logger.daemon.error("could not encode an event: \(String(describing: error), privacy: .public)")
        }
    }

    /// beamd has nothing left to keep once no session runs and nobody is
    /// connected, so it goes, taking its socket with it.
    private func exitIfIdle() {
        guard sessions.isEmpty, connections.isEmpty, control == nil else { return }
        Logger.daemon.info("no sessions left, exiting")
        unlink(path)
        Darwin.exit(EXIT_SUCCESS)
    }
}
