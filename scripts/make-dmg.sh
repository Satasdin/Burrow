#!/bin/zsh
# Makes Burrow.dmg: a disk image that opens with Burrow.app beside a shortcut to Applications, so people drag it in.
# Running the app from the Downloads folder instead put it under App Translocation (16 November), which this avoids.
#   scripts/make-dmg.sh app/build/Burrow.app out/Burrow-macos-arm64.dmg
# Only hdiutil and Finder are used. Burrow is ad-hoc signed and not notarised, so macOS still asks the person to allow
# it once (System Settings › Privacy & Security › Open Anyway); the DMG's background says so.
set -euo pipefail
cd "${0:A:h}/.."
app="${1:?usage: make-dmg.sh <Burrow.app> <out.dmg>}"
out="${2:?usage: make-dmg.sh <Burrow.app> <out.dmg>}"
[[ -d "$app" ]] || { echo "make-dmg: no app at $app" >&2; exit 1; }
name="Burrow"

work="$(mktemp -d)"
trap 'hdiutil detach "$work/mnt" -quiet -force 2>/dev/null || true; rm -rf "$work"' EXIT
stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/$name.app"
ln -s /Applications "$stage/Applications"
cp scripts/dmg/background.tiff "$stage/.background/background.tiff"

hdiutil create -quiet -volname "$name" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
mkdir -p "$work/mnt"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$work/mnt" "$work/rw.dmg"

# The window's look (icon view, size, background, where each icon sits) is kept in the volume's .DS_Store, which only
# Finder writes. Finder addresses the disk by its mount folder. If Finder can't be asked (no Automation permission),
# the image still has the app and the Applications shortcut side by side, just without the background.
if ! osascript <<EOF
tell application "Finder"
  set mounted to POSIX file "$work/mnt" as alias
  open mounted
  set w to container window of mounted
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 840, 548}
  set opts to icon view options of w
  set arrangement of opts to not arranged
  set icon size of opts to 112
  set text size of opts to 13
  set background picture of opts to file ".background:background.tiff" of mounted
  set position of item "$name.app" of mounted to {170, 200}
  set position of item "Applications" of mounted to {470, 200}
  close w
  open mounted
  update mounted without registering applications
  delay 1
  close container window of mounted
end tell
EOF
then
  echo "make-dmg: Finder could not lay out the window (allow Automation for Finder); the image has no background" >&2
fi
sync
# Finder can keep the volume busy for a moment after closing its window.
for try in 1 2 3 4 5; do hdiutil detach -quiet "$work/mnt" && break; sleep 1; done

mkdir -p "${out:h}"
rm -f "$out"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$out"
echo "made $out"
