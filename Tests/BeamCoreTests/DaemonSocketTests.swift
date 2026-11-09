import Darwin
import Foundation
import Testing

@testable import BeamCore

struct DaemonSocketTests {
    @Test func thePathIsTheSameForEveryLaunchAndNamesTheProtocol() {
        let directory = URL(filePath: "/var/folders/xy/T")
        #expect(DaemonSocket.path(in: directory) == "/var/folders/xy/T/beamd-\(DaemonSocket.protocolVersion).sock")
    }

    @Test func listensPrivatelyAndAcceptsConnections() throws {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "beamd-test-\(UUID().uuidString.prefix(8)).sock"
        )
        .path
        // Something left over from a beamd that crashed.
        FileManager.default.createFile(atPath: path, contents: nil)
        let listener = try DaemonSocket.listen(at: path)
        defer {
            close(listener)
            unlink(path)
        }
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(fcntl(listener, F_GETFD) & FD_CLOEXEC != 0)

        let client = try DaemonSocket.connect(to: path)
        defer { close(client) }
        #expect(accept(listener, nil, nil) >= 0)
    }

    @Test func connectingWhereNothingListensFails() {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "beamd-none-\(UUID().uuidString.prefix(8)).sock"
        )
        .path
        #expect(throws: DaemonSocket.Failure.system("connect", ENOENT)) { try DaemonSocket.connect(to: path) }
    }

    /// So a launch can be given a beamd of its own, as make bench does.
    /// Foundation's temporary directory ignores it.
    @Test func theDirectoryIsTMPDIRWhenSet() {
        #expect(DaemonSocket.directory(environment: ["TMPDIR": "/tmp/bench/"]).path == "/tmp/bench")
        #expect(DaemonSocket.directory(environment: [:]) == FileManager.default.temporaryDirectory)
        #expect(DaemonSocket.directory(environment: ["TMPDIR": ""]) == FileManager.default.temporaryDirectory)
    }

    @Test func aSentFrameArrivesWhole() throws {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "beamd-send-\(UUID().uuidString.prefix(8)).sock"
        )
        .path
        let listener = try DaemonSocket.listen(at: path)
        defer {
            close(listener)
            unlink(path)
        }
        let report = AgentReport(pane: Pane.ID(), agent: .claude, event: .waiting(message: "Needs your permission"))
        let frame = try DaemonFrame(.report, encoding: report)
        try DaemonSocket.send(frame, to: path)

        let client = accept(listener, nil, nil)
        #expect(client >= 0)
        defer { close(client) }
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var reader = DaemonFrameReader()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            reader.append(buffer[..<count])
        }
        #expect(try reader.next() == frame)
        #expect(try reader.next() == nil)
    }

    @Test func sendingWhereNothingListensFails() throws {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "beamd-none-\(UUID().uuidString.prefix(8)).sock"
        )
        .path
        #expect(throws: DaemonSocket.Failure.self) { try DaemonSocket.send(DaemonFrame(.report), to: path) }
    }

    /// macOS socket addresses hold 103 bytes of path.
    @Test func aPathTooLongForASocketAddressIsRefused() {
        let long = "/tmp/" + String(repeating: "x", count: 99)
        #expect(throws: DaemonSocket.Failure.pathTooLong) { try DaemonSocket.listen(at: long) }
        #expect(throws: DaemonSocket.Failure.pathTooLong) { try DaemonSocket.send(DaemonFrame(.report), to: long) }
    }

    @Test func theUsersOwnPathFitsInASocketAddress() throws {
        _ = try DaemonSocket.address(DaemonSocket.path(in: DaemonSocket.directory()))
    }

    /// How beamd recognises the listener Beam hands it as descriptor 3.
    /// macOS has no SO_ACCEPTCONN to ask whether a socket listens.
    @Test func onlyASocketBoundToThePathIsTheListener() throws {
        let path = FileManager.default.temporaryDirectory.appending(
            path: "beamd-bound-\(UUID().uuidString.prefix(8)).sock"
        )
        .path
        let listener = try DaemonSocket.listen(at: path)
        defer {
            close(listener)
            unlink(path)
        }
        #expect(DaemonSocket.isBound(listener, to: path))
        #expect(!DaemonSocket.isBound(listener, to: path + ".other"))

        let client = try DaemonSocket.connect(to: path)
        defer { close(client) }
        #expect(!DaemonSocket.isBound(client, to: path))

        var pipe: [Int32] = [0, 0]
        try #require(Darwin.pipe(&pipe) == 0)
        defer { for descriptor in pipe { close(descriptor) } }
        #expect(!DaemonSocket.isBound(pipe[0], to: path))
        #expect(!DaemonSocket.isBound(-1, to: path))
    }
}
