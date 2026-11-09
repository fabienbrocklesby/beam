import BeamCore
import Darwin
import Dispatch
import os

/// One pane's shell: its pty, the processes on it, and the screen they have
/// drawn. At most one pane is attached at a time, and the session runs on
/// whether one is or not, until its shell exits.
final class Session {
    /// Output a slow pane may fall behind by before the session stops reading
    /// its pty, which in turn holds back whatever is printing.
    private static let backlogLimit = 1 << 20

    let pane: Pane.ID
    private let pty: PseudoTerminal
    private let terminal: VirtualTerminal
    private let output: any DispatchSourceRead
    private let input: Writer
    private let exit: any DispatchSourceProcess
    /// Whether `output` is resumed.
    private var reading = true
    /// Set once nothing more is read from the pty: every slave descriptor has
    /// closed, or the shell has exited and its last output has been read.
    private var outputDone = false
    private var ended = false
    private var client: Connection?
    /// Once, after the shell has exited and the attached pane, if any, has
    /// taken the last of its output.
    var onEnd: (() -> Void)?

    init(_ request: AttachRequest) throws {
        pane = request.pane
        terminal = try VirtualTerminal(size: request.size)
        pty = try PseudoTerminal.spawn(
            environment: request.environment, directory: request.workingDirectory, size: request.size)
        input = Writer(descriptor: pty.master)
        output = DispatchSource.makeReadSource(fileDescriptor: pty.master, queue: .main)
        exit = DispatchSource.makeProcessSource(identifier: pty.process, eventMask: .exit, queue: .main)
        terminal.onAnswer = { [weak self] answer in
            // An attached pane's terminal answers for itself.
            guard let self, client == nil else { return }
            input.write(answer)
        }
        output.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readOutput() }
        }
        // Only once nothing watches it, and only as the session goes, so the
        // descriptor is never reused while input or a resize can reach it.
        let master = pty.master
        output.setCancelHandler { Darwin.close(master) }
        exit.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
        output.resume()
        exit.resume()
        Logger.daemon.info("session \(request.pane, privacy: .public) started, pid \(self.pty.process)")
    }

    isolated deinit {
        input.cancel()
        if !reading { output.resume() }
        output.cancel()
        exit.cancel()
    }

    /// Gives `connection` this session's screen at its size, then its live
    /// output. A pane already attached is let go: the newer one wins.
    func attach(_ connection: Connection, size: WindowSize) {
        client?.close()
        client = connection
        connection.onFrame = { [weak self, weak connection] frame in
            guard let self, let connection else { return }
            receive(frame, from: connection)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, client === connection else { return }
            client = nil
            resumeOutput()
        }
        connection.onDrain = { [weak self] in self?.resumeOutput() }
        // Resized first, so the replay is laid out for the pane, and a program
        // that redraws on SIGWINCH does so after it.
        resize(size)
        connection.send(terminal.replay())
    }

    /// Hangs up the shell, as closing its terminal would: its process group
    /// and the terminal's foreground job get SIGHUP. The session ends the
    /// usual way once the shell exits, and closing the pty at the end hangs
    /// up whatever is left on it.
    func hangUp() {
        guard !ended else { return }
        let foreground = tcgetpgrp(pty.master)
        if foreground > 0, foreground != pty.process { killpg(foreground, SIGHUP) }
        killpg(pty.process, SIGHUP)
        Logger.daemon.info("session \(self.pane, privacy: .public) hung up")
    }

    private func receive(_ frame: DaemonFrame, from connection: Connection) {
        switch frame.kind {
        case .input:
            input.write(frame.payload)
        case .resize:
            guard let size = try? WindowSize(bytes: frame.payload) else { return connection.close() }
            resize(size)
        case .attach, .control, .report:
            connection.close()
        }
    }

    private func resize(_ size: WindowSize) {
        pty.resize(size)
        terminal.resize(size)
    }

    private func readOutput() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = read(pty.master, &buffer, buffer.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        // Nothing holds the pty open any more; the exit source ends the
        // session once the shell is reaped.
        guard count > 0 else { return stopOutput() }
        buffer.withUnsafeBytes { terminal.write(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
        guard let client else { return }
        client.send(Array(buffer[..<count]))
        if client.pendingCount > Self.backlogLimit, reading {
            reading = false
            output.suspend()
        }
    }

    private func resumeOutput() {
        guard !reading, !outputDone else { return }
        reading = true
        output.resume()
    }

    private func stopOutput() {
        outputDone = true
        guard reading else { return }
        reading = false
        output.suspend()
    }

    /// The shell has exited: what it printed last still reaches the
    /// terminal and the pane, then the pane is let go, which closes it.
    private func end() {
        guard !ended else { return }
        ended = true
        while !outputDone {
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = read(pty.master, &buffer, buffer.count)
            guard count > 0 else { break }
            buffer.withUnsafeBytes { terminal.write(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            client?.send(Array(buffer[..<count]))
        }
        stopOutput()
        var status: Int32 = 0
        waitpid(pty.process, &status, 0)
        Logger.daemon.info("session \(self.pane, privacy: .public) ended, status \(status)")
        guard let client else {
            onEnd?()
            return
        }
        // Still held here until it closes: nothing else keeps it, and it must
        // live until the pane has taken the last of the output.
        client.onClose = { [weak self] in self?.onEnd?() }
        client.closeAfterSending()
    }
}
