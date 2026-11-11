#!/bin/sh
# Builds build/Beam-<version>.dmg from build/Beam.app: the app and a link to
# /Applications, in a window laid out over a background that shows where to
# drag it. Usage: scripts/dmg.sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Beam.app"
if [ ! -d "$app" ]; then
    echo "error: no build/Beam.app, run make app first" >&2
    exit 1
fi
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
dmg="$root/build/Beam-$version.dmg"

work="$(mktemp -d)"
volume=""
cleanup() {
    if [ -n "$volume" ]; then
        hdiutil detach -quiet -force "$volume" || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

# A writable HFS+ image with room for the app, compressed once laid out.
# -nobrowse keeps the volume out of Finder while it is built.
size_mb=$(($(du -sm "$app" | cut -f1) + 16))
hdiutil create -quiet -fs HFS+ -layout NONE -volname Beam -size "${size_mb}m" "$work/Beam.dmg"
volume="$(hdiutil attach -nobrowse -noautoopen "$work/Beam.dmg" | awk -F '\t' '/\/Volumes\// { print $NF }')"
if [ ! -d "$volume" ]; then
    echo "error: the disk image did not mount" >&2
    exit 1
fi

ditto "$app" "$volume/Beam.app"
ln -s /Applications "$volume/Applications"
mkdir "$volume/.background"
cp "$root/Resources/dmg-background.tiff" "$volume/.background/background.tiff"
# The volume wears the app's icon: .VolumeIcon.icns, flagged as a custom
# icon (0x0400) in the Finder info of the volume's root.
cp "$app/Contents/Resources/Beam.icns" "$volume/.VolumeIcon.icns"
xattr -wx com.apple.FinderInfo \
    0000000000000000040000000000000000000000000000000000000000000000 "$volume"

# The window layout names the background by its place on this volume, so
# it is written last, against the mounted image.
xcrun swiftc -O "$root/scripts/dmg-layout.swift" -o "$work/dmg-layout"
"$work/dmg-layout" "$volume"

hdiutil detach -quiet "$volume"
volume=""
hdiutil convert -quiet "$work/Beam.dmg" -format ULFO -ov -o "$dmg"
echo "$dmg"
