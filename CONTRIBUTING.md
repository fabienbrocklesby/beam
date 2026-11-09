# Contributing to Beam

Thanks for wanting to help. Beam is a small terminal held to a high bar: every
line should be worth maintaining for years. This page says what that bar is
and how changes get in. `make check` enforces most of it, and review covers
the rest.

## Setup

From a clone of the repository:

```sh
git submodule update --init                     # pinned Ghostty
git config core.hooksPath .githooks             # commit checks
xcodebuild -downloadComponent MetalToolchain    # once
make ghostty                                    # libghostty, a few minutes
make run
```

You need Xcode and Zig (the version in `vendor/ghostty/build.zig.zon`).
Nothing else gets installed.

## Structure

```
Sources/BeamCore/        Pure Swift: Foundation, plus CoreGraphics for geometry
                         types. Models, state machines, persistence, env
                         sanitizing, protocol types. No AppKit, no GhosttyKit.
                         Fully unit tested.
Sources/Beam/            The AppKit app, one folder per feature
                         (App/, Ghostty/, Workspace/, Sidebar/, ...).
Sources/Beam/Ghostty/    The only code that imports GhosttyKit or calls ghostty_*.
                         The rest of the app talks to it in Swift.
Sources/BeamDaemon/      beamd, which owns every pane's pty (docs/sessions.md).
Sources/BeamAttach/      beam-attach, the C byte pump each pane runs.
Sources/SessionSpawn/    How beamd starts a session's shell (C, since it forks).
Sources/BeamCLI/         The `beam` helper that agent hooks call.
Tests/                   Swift Testing.
vendor/ghostty/          Pinned submodule (v1.4.0). Never edit.
```

- Dependencies point one way: `Beam` depends on `BeamCore`, never back.
- One primary type per file, named after it. Extensions go in `Type+Topic.swift`.
- Feature folders, not layer folders. No `Utils/`, `Helpers/`, `Managers/`.

## Commands

```sh
make app      # build/Beam.app (release)
make run      # build and launch
make test     # swift test
make format   # swift format, in place
make check    # lint, dash check, tests, release build, bundle budget
make bench    # idle memory against its budget
make launch   # cold launch time against its budget
make ghostty  # rebuild libghostty, only after a submodule bump
```

## Rules

**Keep it simple.** The smallest design that fully solves the problem. No
speculative abstraction: no protocol with one conformer unless it is a test
seam, no generic manager or helper layers, no configuration nobody asked for.

**No dependencies.** Apple frameworks and libghostty only. No third-party Swift
packages, no installed tooling: `swift format`, `swift test` and `footprint`
ship with Xcode. A new dependency needs a written reason that nothing present
does the job, and a maintainer's yes before any code.

**No workaround code.** Not allowed:
- `asyncAfter`, sleeps or retries to dodge a race; polling timers (use dispatch
  sources, kqueue, notifications)
- swizzling, private API
- `!` force unwraps, `try!`, implicitly unwrapped optionals
- `fatalError` or `precondition` for anything recoverable
- `print` (use `Logger`, see `App/Logger+Beam.swift`)
- commented-out code, `TODO` without a linked issue

If an upstream bug forces a workaround, it gets a comment linking the upstream
issue and a check that fails once the bug is fixed.

**Concurrency.** Swift 6 language mode, strict concurrency, warnings are
errors. The `Beam` target defaults to `@MainActor`; code that runs elsewhere is
marked `nonisolated`. C callbacks never assume their thread: each one states it
(see the comment on `GhosttyApp`) and either asserts it with
`MainActor.assumeIsolated` or hops to the main queue.

**Speed.** The main thread never blocks on I/O. No per-frame work in Swift:
libghostty renders. Event-driven everywhere. Measure with Instruments before
optimising. The budgets are in the README; going over one fails `make check`,
`make bench` or `make launch`.

**Apple's standards.** Swift API Design Guidelines for naming. AppKit
conventions: responder chain, target-action, `NSWindowController`. Human
Interface Guidelines for menus, standard shortcuts, window behaviour, Dark Mode
and accessibility. No SwiftUI, no web views, no browser.

**libghostty.**
- Read the C API in `vendor/ghostty/include/ghostty.h`, not upstream docs: the
  pinned tag differs from Ghostty's main branch. Grep for the action tag and its
  payload struct before handling one.
- New actions go in the switch in `Ghostty/GhosttyApp.swift`.
- Never set `wantsLayer` on a `TerminalView` before `ghostty_surface_new`:
  libghostty makes the view layer-hosting itself.

**Writing.** Comments say why, never what. Doc comments on anything
non-obvious. No em or en dashes anywhere (code, comments, docs, commits):
`make check` fails on them.

## Testing

- Logic lives in `BeamCore` and gets a failing test first, then the code.
- Every bug fix gets a regression test.
- UI is checked by using it: run `build/Beam.app/Contents/MacOS/Beam`, follow
  its logs with
  `log stream --level info --predicate 'subsystem == "dev.beam.terminal"'`,
  and look at the change in light and dark mode.
- Memory is `footprint <pid>` (`phys_footprint`), not RSS.

## Making a change

1. For anything bigger than a bug fix, open an issue first and agree on the
   approach. It saves you writing code that will not be merged.
2. Logic changes start with a failing test in `Tests/BeamCoreTests`. Bug fixes
   include a regression test.
3. UI changes include before and after screenshots, in light and dark mode.
4. `make check` passes.
5. Commits are one logical change each, with an imperative subject of at most
   72 characters, a blank line, and a body that says why.

## How pull requests are judged

In this order:

1. **Does it work?** Verified by tests or screenshots, not described.
2. **Is it the simplest thing that works?** Extra abstraction, options or files
   are reasons to send it back.
3. **Does it fit?** Same structure, naming and style as the code around it.
4. **Is it fast?** No new main-thread I/O, polling or per-frame work.

However the code was written, you are its author and should be able to explain
any line of it. Pull requests with code the author has not read, run and
understood are closed without detailed review.

## Licence

By contributing you agree your work is released under the MIT licence. Never
copy code from GPL-licensed projects. Code adapted from Ghostty (MIT) must be
credited in `NOTICE`.
