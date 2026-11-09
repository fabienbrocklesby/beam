import Foundation

extension Process {
    /// Starts the process and waits for it to exit. False when it would not
    /// start, or is still going after `timeout` seconds and is killed.
    ///
    /// Blocks, so call it off the main thread.
    func runAndWait(timeout: TimeInterval) -> Bool {
        let exited = DispatchSemaphore(value: 0)
        terminationHandler = { _ in exited.signal() }
        do {
            try run()
        } catch {
            return false
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            // SIGKILL, since interactive shells ignore SIGTERM.
            kill(processIdentifier, SIGKILL)
            return false
        }
        return true
    }
}
