#!/bin/sh
# Builds libghostty (GhosttyKit.xcframework) and its resources from the pinned
# vendor/ghostty submodule. Needs Zig (see vendor/ghostty/build.zig.zon) and
# Xcode's Metal toolchain: xcodebuild -downloadComponent MetalToolchain
set -eu
cd "$(dirname "$0")/../vendor/ghostty"
zig build \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dxcframework-target=native \
  -Doptimize=ReleaseFast

# beamd links libghostty-vt, which the build above installs into zig-out but
# GhosttyKit does not export. SwiftPM links a prebuilt library only as an
# xcframework whose headers carry a module map. It goes in a folder named for
# the module, where clang also looks, because SwiftPM copies both
# xcframeworks' headers into one folder and GhosttyKit's map is at the top.
headers="$(mktemp -d)"
trap 'rm -rf "$headers"' EXIT
cp -R zig-out/include/ghostty "$headers/"
mkdir "$headers/GhosttyVt"
cat > "$headers/GhosttyVt/module.modulemap" <<'MAP'
module GhosttyVt {
    umbrella header "../ghostty/vt.h"
    export *
}
MAP
rm -rf macos/GhosttyVt.xcframework
xcodebuild -create-xcframework \
  -library zig-out/lib/libghostty-vt.a \
  -headers "$headers" \
  -output macos/GhosttyVt.xcframework >/dev/null
