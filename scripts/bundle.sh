#!/bin/sh
# Builds Beam and assembles build/Beam.app. Usage: scripts/bundle.sh [release|debug]
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-release}"

swift build -c "$config" --package-path "$root"
bin_dir="$(swift build -c "$config" --package-path "$root" --show-bin-path)"

app="$root/build/Beam.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin_dir/Beam" "$app/Contents/MacOS/Beam"
cp "$bin_dir/BeamCLI" "$app/Contents/Helpers/beam"
cp "$bin_dir/BeamDaemon" "$app/Contents/Helpers/beamd"
cp "$bin_dir/BeamAttach" "$app/Contents/Helpers/beam-attach"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/defaults.ghostty" "$app/Contents/Resources/defaults.ghostty"
minos="$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")"

# The icon is an Icon Composer document. actool compiles it to Assets.car (the
# layered icon for macOS 26 and later, rendered sizes for earlier systems) and
# Beam.icns, and lists the keys that name them in a partial Info.plist.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if ! actool "$root/Resources/Beam.icon" --compile "$app/Contents/Resources" \
    --platform macosx --minimum-deployment-target "$minos" --app-icon Beam \
    --output-partial-info-plist "$work/icon.plist" \
    --output-format human-readable-text >"$work/actool.txt"; then
    cat "$work/actool.txt" >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Merge $work/icon.plist" "$app/Contents/Info.plist" >/dev/null
# actool succeeds with an empty partial plist when the document is missing.
if ! plutil -extract CFBundleIconName raw "$app/Contents/Info.plist" >/dev/null 2>&1; then
    echo "error: actool compiled no app icon from Resources/Beam.icon" >&2
    exit 1
fi

# macOS draws an app with the design of the SDK its binary says it was built
# against. Swift Build writes the deployment target there instead
# (https://github.com/swiftlang/swift-build/issues/1887), which gets Beam the
# pre-Liquid Glass design, so write the real SDK. Once the binary already
# says so the bug is fixed and this step should go.
sdk="$(xcrun --sdk macosx --show-sdk-version)"
if vtool -show-build "$app/Contents/MacOS/Beam" | grep -qx " *sdk $sdk"; then
    echo "swift-build#1887 looks fixed: remove the vtool step from scripts/bundle.sh" >&2
    exit 1
fi
vtool -set-build-version macos "$minos" "$sdk" -replace \
    -output "$app/Contents/MacOS/Beam" "$app/Contents/MacOS/Beam" 2>/dev/null

# libghostty finds shell integration and terminfo by looking for
# Contents/Resources/terminfo next to the executable.
share="$root/vendor/ghostty/zig-out/share"
cp -R "$share/ghostty" "$share/terminfo" "$app/Contents/Resources/"

# A release ships without debug symbols: they record absolute build paths and
# serve nothing without the object files they point to. strip warns that it
# breaks the linker's signature, which the signing below replaces.
if [ "$config" = release ]; then
    strip -S "$app/Contents/MacOS/Beam" "$app/Contents/Helpers/beam" \
        "$app/Contents/Helpers/beamd" "$app/Contents/Helpers/beam-attach" 2>/dev/null
fi

# Nested code is signed before the bundle that seals it.
for helper in beam beamd beam-attach; do
    codesign --force --sign - "$app/Contents/Helpers/$helper" >/dev/null
done
codesign --force --sign - "$app" >/dev/null
echo "$app"
