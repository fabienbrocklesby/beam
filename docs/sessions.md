# Sessions that survive quit

Quitting Beam, or Beam crashing, leaves every shell and agent running.
Relaunching puts each pane back exactly as it was: the same process, the same
screen, the same scrollback.

## Shape

```
Beam.app                          beamd                        session
 Ghostty surface (pane P)          one per user, on demand       login shell, agents
   pty  <->  beam-attach  <------>  session P: pty master  <-->  pty slave
             (C byte pump)          + libghostty-vt terminal
 DaemonClient  <-- control -------> sessions, latest agent report per pane
 beam hook (agent hooks)  -- report --^
```

- **beamd** (`Contents/Helpers/beamd`, Swift) owns every pane's pty and keeps
  its screen in a headless libghostty-vt terminal fed with all of the session's
  output. It knows nothing about workspaces or agents.
- **beam-attach** (`Contents/Helpers/beam-attach`, C) is the command each
  Ghostty surface runs. It puts its own tty in raw mode and pumps bytes between
  that tty and the session, so Ghostty renders, encodes keys and answers
  queries exactly as it would for a plain shell.
- **Beam** decides what a pane runs and when a session ends. libghostty-vt
  never enters `Beam`, and GhosttyKit never enters `beamd`.

## Lifecycle

**Daemon.** One socket, `$TMPDIR/beamd-<protocol version>.sock`, mode 0600
(read from the environment: Foundation's temporary folder ignores `$TMPDIR`).
At launch Beam connects to it. If nothing answers, Beam binds and listens on
the path itself, then spawns beamd in its own session with that listening
socket as an inherited descriptor. Connections queue in the kernel until beamd
accepts them, so there is no readiness wait. beamd exits once it has no
sessions and no Beam connected. A new protocol version means a new socket
path, so a newer Beam never talks to an older beamd; that older beamd's
sessions keep running until they end, unseen.

**Create and attach are one step.** A surface runs `beam-attach`. It sends
beamd its pane ID (`BEAM_PANE_ID`), window size, working directory and whole
environment. If the session exists it attaches; if not, beamd creates it by
spawning `$SHELL` as a login shell (argv[0] `-zsh`) in a new session with the
pty as its controlling terminal, with exactly that environment and directory.
beamd forks, and the child calls `setsid` and takes the pty with `TIOCSCTTY`
before it execs, as Ghostty does: `posix_spawn` opens files before it starts
the session, so its child never gets a controlling terminal, and without one
Ctrl+C, Ctrl+Z and resizes reach nobody. beamd keeps its own slave descriptor
open until the child has started (closing it first resets the window size to
0x0) and sets `IUTF8`, as Ghostty does.
beam-attach already runs under the `/usr/bin/login -flp` that Ghostty wraps
every macOS command in, so the environment is a login one and carries
Ghostty's `TERM`, `TERMINFO` and `GHOSTTY_RESOURCES_DIR`. Agent commands are
still typed through the surface's `initial_input`, which reaches the session
through the pump.

**Replay.** On every attach beamd resizes the session's pty and terminal to
the client's size first, so the agent redraws once at the right size, then
writes: a full reset (clearing the screen and scrollback, which also wipes the
"Last login" line `login` printed for beam-attach), then the formatter's VT
output of the terminal (scrollback, styles, modes, scrolling region,
tabstops, kitty keyboard flags, pwd as OSC 7, cursor), then OSC 4 for any
palette entry an app changed, then the title, then the terminal's unfinished
escape sequence if a read ended inside one, then live output. The formatter's
own palette option writes all 256 entries, which would replace Beam's theme,
so it stays off. beamd handles a session's reads and its attach on one serial
queue, so no output falls between the replay and the stream. Replayed modes
make Ghostty report its colour scheme and focus straight away; those reports
reach the agent, as they would in a fresh terminal.

**Queries.** While attached, Ghostty answers terminal queries (device
attributes, cursor position, colours) through the pump, and beamd drops its
own terminal's answers. While detached, beamd's terminal answers them, so an
agent that queries the terminal never hangs.

**Detach.** Quitting Beam or a crash frees the surfaces, Ghostty hangs up
beam-attach, and beamd sees the attach connection close. The session keeps
running. Nothing else detaches a session.

**End.** Beam ends a session when its pane leaves the workspace store
(closing a pane or a workspace), never when a surface is merely freed.
Beam > Quit and End Sessions ends all of them, then quits. When a session's
shell exits on its own, beamd reaps it and closes the attach connection,
beam-attach exits, and the pane closes as usual.

**Restore.** Beam asks beamd for its live sessions before rebuilding panes.
A pane with a live session attaches with no initial input. A pane without one
starts a new session and types its resume command (after a reboot or logout,
every pane takes this path). Live sessions with no pane in
a state file that loaded are ended; if the state file failed to load, they are
left alone.

**Fallback.** If beam-attach cannot reach beamd, it says so in one line and
execs `$SHELL` as a login shell itself, so the pane still works; that pane
just does not survive quit. If Beam itself cannot reach or start beamd at
launch, or beamd goes away before it answers, every pane runs its shell
directly: agents start without hooks, and quitting asks when a process is
running.

## Protocol

Every connection opens with one frame naming its kind: `u8 kind, u32 length
(little endian), payload`.

| Kind | From | Payload, then |
|---|---|---|
| attach (1) | beam-attach | A `WindowSize` (four little-endian u16: cols, rows, width px, height px), then NUL-terminated: pane ID, cwd, one `KEY=value` per environment variable. Then client frames `input` (2) and `resize` (3); beamd writes raw output back, and closes the connection when the session ends. |
| control (4) | Beam | A `ControlRequest` as JSON. Every message after it, both ways, is another control frame: `list`, `end(pane)`, `endAll` from Beam; `sessions([pane, latest reports])` and `report(AgentReport)` from beamd. |
| report (5) | `beam hook` | One `AgentReport` as JSON. beamd closes the connection after it. |

Control messages are framed rather than newline-delimited, so both sides
read every connection with the same frame reader. The framing, the attach
header, the control messages and the non-blocking `Writer` both sides send
with live in `BeamCore` with tests. beam-attach writes the same bytes from C.

## Agent state

`BEAM_SOCKET` names beamd's socket, so hooks in a session that outlived Beam
still land. beamd keeps the latest `started` report and the latest state
report per session, sends them with `sessions` when Beam connects, and relays
new ones while Beam is connected. A relaunched Beam therefore shows which
agents finished or are waiting while it was quit. There are no notifications
while Beam is not running. `AgentNotifier` still clears delivered
notifications at launch: the sidebar shows the state then.

## Shell integration

Ghostty injects its shell integration only into a command it recognises as a
shell, and `beam-attach` is not one. Beam adds the zsh injection to the pane
environment itself, as Ghostty does: `ZDOTDIR` points at the bundled
`shell-integration/zsh`, an inherited `ZDOTDIR` moves to
`GHOSTTY_ZSH_ZDOTDIR`, and `GHOSTTY_SHELL_FEATURES` matches what Ghostty sets.
That keeps the OSC 7 working directory, prompt marks (which drive
close confirmation) and titles. bash and fish users get no shell integration
under beamd yet.

The formatter writes no prompt marks, so a replayed idle shell would read as
a running command and ask before closing (with Ghostty's default
`confirm-close-surface`). beamd ends the replay with OSC 133;B when its own
terminal has the cursor at the prompt.

## Known limits

- A session restored while a full-screen program (vim, less, htop) is on the
  alternate screen gets that screen back; the primary screen behind it starts
  empty in the pane (beamd still has it). The formatter only writes the
  active screen. Claude Code 2.1 runs full screen on the alternate screen,
  so this reaches it: after a reattach, the shell output from before
  `claude` started is gone from the pane once Claude quits.
- Prompt marks on replayed rows are not carried, only the cursor's, so
  jumping between prompts does not reach history from before a reattach.
- Bell, clipboard writes and desktop notifications an agent sends while
  detached are dropped.
- Sessions do not survive logout or reboot. libghostty-vt snapshots could
  make the screen survive later; the processes cannot.
- One attachment per session.
- Panes are created when their workspace is first shown. A live session that
  ends before then leaves its pane to start a fresh shell, with nothing
  typed.
- An `end(pane)` that reaches beamd before that pane's beam-attach has
  attached finds no session, so the session the attach then creates stays
  until the next launch ends it as an orphan.
- A done state the user looked at before quitting shows again after a
  relaunch (beamd keeps the report), until the pane is looked at again.
- An agent that exits while Beam is quit keeps its pane's command, so the
  next launch without that session (after a reboot) resumes it.
- Quit and End Sessions asks first only for processes running in panes that
  have been shown; sessions of workspaces not yet shown end without asking.

## Testing

- `BeamCore`: framing, attach header, control messages, report store,
  pane environment (zsh injection), restore choice (attach or resume).
- `BeamDaemonTests`: the replay through a real libghostty-vt terminal.
- By hand, through beam-attach: stream a long Claude Code response, resize
  mid-stream, scroll back, paste an image path, use an IME, Ctrl+C, Ctrl+Z,
  quit and relaunch mid-stream, close a pane, Quit and End Sessions.
- `make bench` runs Beam with its own `TMPDIR`, so it gets its own beamd, and
  ends that beamd's sessions when it is done.
- Memory: beamd's footprint counts toward the 4-pane budget.
