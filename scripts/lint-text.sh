#!/bin/sh
# Fails if any tracked file outside vendor/ contains an em or en dash.
# House style: use a comma, a colon, or rewrite the sentence.
set -eu
cd "$(dirname "$0")/.."
dashes="$(printf '\342\200\223|\342\200\224')"
# git grep exits 0 on a match, 1 on none, and above 1 on an error.
status=0
git grep -nIE "$dashes" -- . ':!vendor' || status=$?
case $status in
  0) echo "error: em or en dash found (house style: comma, colon, or rewrite)" >&2; exit 1 ;;
  1) ;;
  *) exit "$status" ;;
esac
