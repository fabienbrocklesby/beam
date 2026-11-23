import BeamCore
import Foundation
import Testing

/// A class, so each test's instance can take its folder with it.
final class InstanceLockTests {
    /// This test's stand-in for the user's temporary folder.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "beam-lock-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func theFirstBeamClaimsItsFolder() {
        guard case .made = InstanceLock.claim(in: folder, process: 4242) else {
            Issue.record("the folder was free to claim")
            return
        }
    }

    /// Two Beams on one beamd: the second used to take the first's
    /// connection, which left the first without agent state, and ended the
    /// sessions it did not know.
    @Test func aSecondBeamLearnsWhichProcessHoldsTheFolder() {
        guard case .made(let lock) = InstanceLock.claim(in: folder, process: 4242) else {
            Issue.record("the folder was free to claim")
            return
        }
        #expect(InstanceLock.claim(in: folder, process: 5151) == .taken(by: 4242))
        // The first claim still stands after the second was turned away.
        #expect(InstanceLock.claim(in: folder, process: 6060) == .taken(by: 4242))
        withExtendedLifetime(lock) {}
    }

    @Test func theFolderIsFreeOnceItsHolderIsGone() {
        do {
            guard case .made = InstanceLock.claim(in: folder, process: 4242) else {
                Issue.record("the folder was free to claim")
                return
            }
        }
        guard case .made(let next) = InstanceLock.claim(in: folder, process: 5151) else {
            Issue.record("the first holder had gone")
            return
        }
        #expect(InstanceLock.claim(in: folder, process: 6060) == .taken(by: 5151))
        withExtendedLifetime(next) {}
    }

    @Test func beamsWithTheirOwnFoldersDoNotMeet() throws {
        let other = folder.appending(path: "other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        guard case .made(let first) = InstanceLock.claim(in: folder, process: 4242),
            case .made(let second) = InstanceLock.claim(in: other, process: 5151)
        else {
            Issue.record("each folder was free to claim")
            return
        }
        withExtendedLifetime((first, second)) {}
    }

    /// beamd outlives the Beam that starts it. Were it to inherit the lock,
    /// no later Beam could claim the folder.
    @Test func aProgramTheHolderStartsDoesNotKeepTheClaim() throws {
        var child: pid_t = 0
        do {
            guard case .made(let lock) = InstanceLock.claim(in: folder, process: 4242) else {
                Issue.record("the folder was free to claim")
                return
            }
            // Spawned plainly, so it inherits every descriptor not marked to close.
            let arguments: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("30"), nil]
            defer { for argument in arguments { free(argument) } }
            let spawned = posix_spawn(&child, "/bin/sleep", nil, nil, arguments, nil)
            try #require(spawned == 0)
            withExtendedLifetime(lock) {}
        }
        defer {
            kill(child, SIGKILL)
            waitpid(child, nil, 0)
        }
        guard case .made = InstanceLock.claim(in: folder, process: 5151) else {
            Issue.record("the program the holder started kept its claim")
            return
        }
    }

    /// Beam still starts when it cannot keep a lock: that is the lesser harm.
    @Test func aFolderThatCannotHoldALockStopsNothing() {
        #expect(InstanceLock.claim(in: folder.appending(path: "missing"), process: 4242) == .unavailable)
    }
}
