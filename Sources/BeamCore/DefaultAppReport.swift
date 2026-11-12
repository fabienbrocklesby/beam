import Foundation

/// What Beam > Make Beam the Default App… says once macOS has answered for
/// each kind of file.
public struct DefaultAppReport: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The app at this path opens the kind now.
        case opens(String)
        /// macOS left the current app: it asks before it replaces some
        /// defaults, and plain text always, and answers a kept app, or a
        /// question it could not ask, with a cancel.
        case kept
        case failed(String)

        /// The outcome of an error from `NSWorkspace.setDefaultApplication`.
        public init(_ error: any Error) {
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            let cancelled =
                (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
                || (underlying?.domain == NSOSStatusErrorDomain && underlying?.code == userCanceledErr)
            self = cancelled ? .kept : .failed(error.localizedDescription)
        }
    }

    public let message: String
    /// One line per note, empty when there is nothing more to say.
    public let details: String

    /// - Parameters:
    ///   - outcomes: Each kind as a sentence names it, in order.
    ///   - beam: The path of the copy of Beam that asked.
    public init(_ outcomes: [(kind: String, outcome: Outcome)], beam: String) {
        var set: [String] = []
        var kept: [String] = []
        var failures: [String] = []
        // A default names a bundle ID and a version, so at equal versions
        // Launch Services can pick another copy of Beam.
        var copies: [(path: String, kinds: [String])] = []
        for (kind, outcome) in outcomes {
            switch outcome {
            case .opens(let path):
                set.append(kind)
                guard path != beam else { continue }
                if let index = copies.firstIndex(where: { $0.path == path }) {
                    copies[index].kinds.append(kind)
                } else {
                    copies.append((path, [kind]))
                }
            case .kept:
                kept.append(kind)
            case .failed(let reason):
                failures.append("\(kind): \(reason)")
            }
        }
        message =
            set.isEmpty ? "Beam was not made the default app." : "Beam is now the default app for \(Self.list(set))."
        var notes = copies.map { "Finder will open \(Self.list($0.kinds)) in the copy of Beam at \($0.path)." }
        if !kept.isEmpty { notes.append("macOS kept the current app for \(Self.list(kept)).") }
        details = (notes + failures).joined(separator: "\n")
    }

    /// "a", "a and b", "a, b and c", the same in every locale.
    private static func list(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
