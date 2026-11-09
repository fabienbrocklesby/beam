#!/bin/sh
# Launches build/Beam.app cold several times and prints how long each run took
# from its process starting to the first prompt in its pane, as Beam logs it,
# then the median and the slowest. Fails when the median is over the budget in
# README.md.
#
# Cold means nothing of Beam is running: each run has an empty home and its
# own TMPDIR, as in bench.sh, so Beam restores nothing and starts a beamd and a
# shell of its own. The shell is zsh reading no user config (an empty ZDOTDIR):
# dotfiles take as long in any terminal, and often longer than Beam itself.
# Usage: scripts/launch.sh [runs]
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
exe="$root/build/Beam.app/Contents/MacOS/Beam"
runs="${1:-10}"
budget_ms=400

# Every run opens Beam at its default window size, as bench.sh does, and the
# saved frame goes back after.
domain=dev.beam.terminal
frame_key="NSWindow Frame Main"
saved_frame="$(defaults read "$domain" "$frame_key" 2>/dev/null || true)"
work="$(mktemp -d)"
pid=""
daemon=""
stream=""
cleanup() {
  # Ending beamd closes its pty masters, which hangs up the shell it ran.
  kill $pid $daemon $stream 2>/dev/null || true
  wait 2>/dev/null || true
  if [ -n "$saved_frame" ]; then
    defaults write "$domain" "$frame_key" "$saved_frame"
  else
    defaults delete "$domain" "$frame_key" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
defaults write "$domain" "$frame_key" "0 0 1100 700"

run=1
while [ "$run" -le "$runs" ]; do
  dir="$work/$run"
  mkdir -p "$dir/home" "$dir/tmp" "$dir/zsh"
  mkfifo "$dir/log"
  # A run that never reaches a prompt ends with the stream.
  /usr/bin/log stream --style compact --timeout 30 \
    --predicate 'subsystem == "dev.beam.terminal" AND eventMessage BEGINSWITH "first prompt"' >"$dir/log" &
  stream=$!
  exec 3<"$dir/log"
  # The stream prints its filter once it is listening.
  read -r _ <&3

  CFFIXED_USER_HOME="$dir/home" TMPDIR="$dir/tmp/" ZDOTDIR="$dir/zsh" "$exe" >/dev/null 2>&1 &
  pid=$!
  ms=""
  while [ -z "$ms" ] && read -r line <&3; do
    case $line in
      *"Beam[$pid:"*) ms="$(printf '%s\n' "$line" | sed -n 's/.*first prompt \([0-9]*\)ms after launch.*/\1/p')" ;;
    esac
  done
  exec 3<&-

  # Found while Beam is its parent: once Beam exits, launchd adopts it.
  daemon="$(pgrep -P "$pid" -x beamd || true)"
  kill $pid $daemon $stream 2>/dev/null || true
  wait $pid $stream 2>/dev/null || true
  pid=""
  stream=""
  if [ -z "$ms" ]; then
    echo "error: run $run logged no first prompt (is zsh the login shell?)" >&2
    exit 1
  fi
  echo "run $run: ${ms}ms"
  echo "$ms" >>"$work/times"
  run=$((run + 1))
done

median_ms="$(sort -n "$work/times" | sed -n "$(((runs + 1) / 2))p")"
slowest_ms="$(sort -n "$work/times" | tail -1)"
echo "launch:  ${median_ms}ms median, ${slowest_ms}ms slowest (budget ${budget_ms}ms)"
if [ "$median_ms" -ge "$budget_ms" ]; then
  echo "error: median launch ${median_ms}ms, budget is ${budget_ms}ms" >&2
  exit 1
fi
