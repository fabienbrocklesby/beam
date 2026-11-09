import BeamCore
import Foundation
import os

/// How long Beam took to launch: from the kernel starting its process to the
/// first prompt in a pane, logged once for `scripts/launch.sh` and Console.
/// The prompt is marked by the first working directory a pane reports, which
/// Ghostty's shell integration sends just before the shell prints it; the
/// renderer draws it on its next frame.
enum LaunchTime {
    private static var logged = false

    static func promptReached() {
        guard !logged else { return }
        logged = true
        guard let start = ProcessInfo.startDate(of: getpid()) else { return }
        let milliseconds = Int((Date().timeIntervalSince(start) * 1000).rounded())
        Logger.app.notice("first prompt \(milliseconds)ms after launch")
    }
}
