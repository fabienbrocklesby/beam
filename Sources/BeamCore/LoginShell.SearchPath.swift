import Foundation

extension LoginShell {
    /// A `PATH` to look programs up on, and whose it is.
    public struct SearchPath: Equatable, Sendable {
        public let path: String
        /// False when the login shell failed or hung and Beam's own `PATH`
        /// stands in, which finds only what is in the system's folders. The
        /// shell is then worth asking again: one that is slow while the Mac
        /// starts up answers once it has settled.
        public let isFromLoginShell: Bool

        public init(path: String, isFromLoginShell: Bool) {
            self.path = path
            self.isFromLoginShell = isFromLoginShell
        }
    }

    /// The `PATH` `shell` builds (see `path`), or the one in `environment`
    /// when it gives none.
    ///
    /// Blocks until the shell exits, so call it off the main thread.
    public static func searchPath(
        shell: String, environment: [String: String], timeout: TimeInterval
    ) -> SearchPath {
        if let path = path(shell: shell, environment: environment, timeout: timeout) {
            return SearchPath(path: path, isFromLoginShell: true)
        }
        return SearchPath(path: environment["PATH"] ?? "", isFromLoginShell: false)
    }
}
