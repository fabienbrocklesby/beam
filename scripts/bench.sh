#!/bin/sh
# Launches build/Beam.app, lets it reach steady state, prints its memory and
# its beamd's the way Activity Monitor counts it (physical footprint), then
# quits both. With no command it measures an idle shell and fails when the two
# together go over the budget in README.md.
# Usage: scripts/bench.sh [command]   e.g. scripts/bench.sh claude
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
exe="$root/build/Beam.app/Contents/MacOS/Beam"
settle="${BENCH_SETTLE:-6}"
idle_budget_mb=80

# An empty home for the run, so Beam restores no saved workspaces and the
# measurement is always one pane, and a Beam already running keeps its
# state.json to itself. Foundation resolves NSHomeDirectory and Application
# Support from CFFIXED_USER_HOME; the shell still gets the real $HOME. Its own
# TMPDIR gives the run its own beamd socket, so Beam starts a fresh beamd
# instead of attaching to the sessions of one already running.
bench_dir="$(mktemp -d)"
mkdir "$bench_dir/home" "$bench_dir/tmp"
export CFFIXED_USER_HOME="$bench_dir/home" TMPDIR="$bench_dir/tmp/"

# The window's size sets most of the reading: each pane renders into three
# IOSurfaces at its full pixel size, so a filled 13 inch Retina screen reads
# about 10MB more than the default window, and a 1x display about 25MB less.
# The saved frame is in the real defaults, which CFFIXED_USER_HOME does not
# move, so the run opens Beam at its default size and puts the frame back.
domain=dev.beam.terminal
frame_key="NSWindow Frame Main"
saved_frame="$(defaults read "$domain" "$frame_key" 2>/dev/null || true)"
pid=""
daemon=""
cleanup() {
  # Ending beamd closes its pty masters, which hangs up the sessions it ran.
  kill $pid $daemon 2>/dev/null || true
  wait $pid 2>/dev/null || true
  if [ -n "$saved_frame" ]; then
    defaults write "$domain" "$frame_key" "$saved_frame"
  else
    defaults delete "$domain" "$frame_key" 2>/dev/null || true
  fi
  rm -rf "$bench_dir"
}
trap cleanup EXIT
defaults write "$domain" "$frame_key" "0 0 1100 700"

if [ $# -gt 0 ]; then
  "$exe" --command="$1" >/dev/null 2>&1 &
else
  "$exe" >/dev/null 2>&1 &
fi
pid=$!

# A fixed settle time is the measurement protocol: the shell and renderer
# need to finish starting before the footprint means anything.
sleep "$settle"
if ! kill -0 "$pid" 2>/dev/null; then
  echo "error: Beam exited before it could be measured" >&2
  exit 1
fi
if [ ! -f "$bench_dir/home/Library/Application Support/Beam/state.json" ]; then
  echo "error: Beam did not use the bench home, so it may have restored saved workspaces" >&2
  exit 1
fi
# Found while Beam is its parent: once Beam exits, launchd adopts it.
daemon="$(pgrep -P "$pid" -x beamd || true)"
if [ -z "$daemon" ]; then
  echo "error: Beam started no beamd, so its panes run without one" >&2
  exit 1
fi
bytes() { footprint --format bytes "$1" | awk -v key="$2" '$1 == key":" {print $2}'; }
mb() { echo $(($(bytes "$1" "$2") / 1048576)); }
beam_mb=$(mb "$pid" phys_footprint)
daemon_mb=$(mb "$daemon" phys_footprint)
total_mb=$((beam_mb + daemon_mb))
echo "footprint: ${beam_mb}MB (peak $(mb "$pid" phys_footprint_peak)MB)"
echo "beamd:     ${daemon_mb}MB (peak $(mb "$daemon" phys_footprint_peak)MB)"
du -sh "$root/build/Beam.app" | awk '{print "bundle:    " $1}'

if [ $# -eq 0 ] && [ "$total_mb" -ge "$idle_budget_mb" ]; then
  echo "error: idle footprint ${total_mb}MB with beamd, budget is ${idle_budget_mb}MB" >&2
  exit 1
fi
