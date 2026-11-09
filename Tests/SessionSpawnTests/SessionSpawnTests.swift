import Darwin
import SessionSpawn
import Testing

struct SessionSpawnTests {
    /// The pty has to be the child's controlling terminal, or the line
    /// discipline signals nobody and Ctrl+C, Ctrl+Z and resizes never reach a
    /// shell's jobs. zsh, because bash takes its terminal itself at startup,
    /// which would hide a child that was not given one.
    @Test func ctrlCTypedIntoThePtyInterruptsTheChild() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        defer { close(master) }
        let arguments = ["zsh", "-f", "-c", "print ready; exec cat"]
        let pointers = arguments.map { strdup($0) } + [nil]
        defer { for pointer in pointers { free(pointer) } }
        let environment: [UnsafeMutablePointer<CChar>?] = [nil]
        let child = session_spawn("/bin/zsh", pointers, environment, slave, "/")
        close(slave)
        try #require(child > 0)

        // Ready once it prints: by then it has taken the terminal, or never will.
        var output: [UInt8] = []
        while !String(decoding: output, as: UTF8.self).contains("ready") {
            var buffer = [UInt8](repeating: 0, count: 256)
            let count = read(master, &buffer, buffer.count)
            try #require(count > 0)
            output += buffer[..<count]
        }
        // Ctrl+C. Then Ctrl+D, which ends cat on its own if the interrupt
        // went nowhere, so a failure cannot hang the test; in one write the
        // line discipline drops it along with the interrupted input.
        #expect(write(master, [0x03], 1) == 1)
        #expect(write(master, [0x04], 1) == 1)

        var status: Int32 = 0
        try #require(waitpid(child, &status, 0) == child)
        // WTERMSIG, which Swift does not import: the low seven bits.
        #expect(status & 0x7f == SIGINT)
    }
}
