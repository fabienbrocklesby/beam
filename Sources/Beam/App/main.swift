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

// One Beam per beamd: a second would take the first's connection to it and
// end the sessions the first is showing. So a Beam that finds the folder
// claimed brings the holder forward and goes. A top level constant, because
// the claim lasts only as long as something holds it.
let instance = InstanceLock.claim(in: DaemonSocket.directory())
switch instance {
case .made:
    break
case .taken(let holder):
    if let holder, let running = NSRunningApplication(processIdentifier: holder) {
        // Asked twice, because macOS grants each request in one case only.
        // Started from a shell, this process is no app until NSApplication
        // exists, and only then is the first granted. Started by Launch
        // Services it is an app from the outset, the first is refused, and
        // the second is granted because this app yields to the holder.
        running.activate()
        NSApplication.shared.yieldActivation(to: running)
        running.activate()
        exit(EXIT_SUCCESS)
    }
    // A Beam that will not open is worse than two that share a beamd.
    Logger.app.error("another process holds Beam's lock but is no running app, so starting beside it")
case .unavailable:
    Logger.app.error("could not take Beam's lock, so a second Beam would start beside this one")
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
