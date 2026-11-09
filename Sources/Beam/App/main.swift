import AppKit
import BeamCore
import os

// Panes inherit Beam's environment, so drop whatever describes the program
// that launched Beam. This must run before GhosttyApp: libghostty snapshots
// the environment when it starts and can only add to it per pane.
let inherited = ProcessInfo.processInfo.environment
let sanitized = PaneEnvironment.sanitized(inherited, home: NSHomeDirectory())
for name in inherited.keys where sanitized[name] == nil {
    unsetenv(name)
}
if let path = sanitized["PATH"], path != inherited["PATH"] {
    setenv("PATH", path, 1)
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)

guard let ghostty = GhosttyApp() else {
    // The run loop has not started, so bring Beam forward or the alert opens
    // behind whatever app launched it.
    application.activate()
    let alert = NSAlert()
    alert.messageText = "Beam could not start its terminal engine."
    alert.informativeText = "Console.app has the details under the dev.beam.terminal subsystem."
    alert.runModal()
    exit(EXIT_FAILURE)
}

let delegate = AppDelegate(ghostty: ghostty)
application.delegate = delegate
application.run()
