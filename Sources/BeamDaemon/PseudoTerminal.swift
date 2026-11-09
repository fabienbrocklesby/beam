import BeamCore
import Darwin
import Foundation
import SessionSpawn

/// A pty with the user's login shell on its far end, in a session of its own
/// with the pty as its controlling terminal, as a terminal starts one.
struct PseudoTerminal {
    enum Failure: Error {
        case system(String, Int32)
    }

    /// Non-blocking, and not inherited by anything beamd starts later.
    let master: Int32
    let process: pid_t

    /// Starts `$SHELL` from `environment` (the passwd entry's shell without
    /// one) as a login shell, with exactly that environment, in `directory`
    /// (home when it has gone).
    static func spawn(environment: [String], directory: String, size: WindowSize) throws -> PseudoTerminal {
        var master: Int32 = -1
        var slave: Int32 = -1
        var window = winsize(size)
        guard openpty(&master, &slave, nil, nil, &window) == 0 else { throw Failure.system("openpty", errno) }
        // Only after the spawn: closing the last slave descriptor resets the
        // window size.
        defer { close(slave) }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        // So the line discipline erases a whole character, not a byte of one,
        // as in Ghostty's own ptys.
        var attributes = termios()
        if tcgetattr(slave, &attributes) == 0 {
            attributes.c_iflag |= tcflag_t(IUTF8)
            tcsetattr(slave, TCSANOW, &attributes)
        }

        let shell = shell(in: environment)
        var isDirectory: ObjCBool = false
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let start =
            FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue
            ? directory : home

        // A leading dash makes it a login shell, as `exec -l` does.
        let arguments = ["-" + (shell as NSString).lastPathComponent]
        let process = withCStrings(arguments) { argv in
            withCStrings(environment) { envp in
                session_spawn(shell, argv, envp, slave, start)
            }
        }
        guard process > 0 else {
            let error = errno
            close(master)
            throw Failure.system("fork", error)
        }
        return PseudoTerminal(master: master, process: process)
    }

    /// Tells the pty, and so the shell's foreground job, the new size.
    func resize(_ size: WindowSize) {
        var window = Self.winsize(size)
        _ = ioctl(master, TIOCSWINSZ, &window)
    }

    private static func shell(in environment: [String]) -> String {
        if let entry = environment.last(where: { $0.hasPrefix("SHELL=") }), entry.count > "SHELL=".count {
            return String(entry.dropFirst("SHELL=".count))
        }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return "/bin/zsh"
    }

    private static func winsize(_ size: WindowSize) -> Darwin.winsize {
        Darwin.winsize(ws_row: size.rows, ws_col: size.columns, ws_xpixel: size.width, ws_ypixel: size.height)
    }

    /// `strings` as a NULL-terminated C array, alive for `body`.
    private static func withCStrings<Result>(
        _ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> Result
    ) -> Result {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { for pointer in pointers { free(pointer) } }
        return body(pointers)
    }
}
