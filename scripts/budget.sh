#!/bin/sh
# Fails if build/Beam.app is over the bundle size budget in README.md.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
budget_mb=30

size_kb="$(du -sk "$root/build/Beam.app" | awk '{print $1}')"
size_mb=$((size_kb / 1024))
if [ "$size_kb" -ge $((budget_mb * 1024)) ]; then
  echo "error: Beam.app is ${size_mb}MB, budget is ${budget_mb}MB" >&2
  exit 1
fi
echo "bundle: ${size_mb}MB (budget ${budget_mb}MB)"
