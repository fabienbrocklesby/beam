import BeamCore
import Foundation

// `beam hook <agent>`, run by the hooks Beam gives the agents it starts (see
// AgentHooks) with the hook's payload on stdin. Tells beamd, which runs the
// pane's session and passes reports on to Beam, what the payload means for
// the pane.
//
// Prints nothing and exits 0 whatever becomes of the report: agents show a
// failing hook to the user, and Codex reads a Stop hook's output as a
// decision. The agent carries on the same whether or not Beam heard.

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, arguments[0] == "hook", let agent = Agent(rawValue: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: beam hook <claude|codex>\n".utf8))
    exit(EX_USAGE)
}

// Set in every pane Beam starts; an agent run anywhere else has nobody to tell.
let environment = ProcessInfo.processInfo.environment
guard let uuid = environment["BEAM_PANE_ID"].flatMap(UUID.init(uuidString:)),
    let socket = environment["BEAM_SOCKET"]
else { exit(EXIT_SUCCESS) }

let payload = FileHandle.standardInput.readDataToEndOfFile()
if let report = AgentHook.report(from: payload, pane: Pane.ID(uuid: uuid), agent: agent) {
    // Fails only when beamd has gone, and the session with it.
    try? DaemonSocket.send(DaemonFrame(.report, encoding: report), to: socket)
}
