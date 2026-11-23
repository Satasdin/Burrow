#!/bin/zsh
# Builds the terminal program and the desktop app and publishes them as a GitHub release.
#   scripts/release.sh v1.0.0
set -euo pipefail
cd "${0:A:h}/.."
version="${1:?usage: release.sh vX.Y.Z}"
tag="camr-$version"
out="$(mktemp -d)"

swift build -c release --product camr
cp .build/release/camr "$out/camr"
codesign --force --sign - "$out/camr"
tar -czf "$out/camr-macos-arm64.tar.gz" -C "$out" camr

app/build.sh
# The zip is what install.sh --app fetches with curl; the DMG is the download for a browser, with the drag-to-Applications window.
ditto -c -k --sequesterRsrc --keepParent app/build/CAMR.app "$out/CAMR-macos-arm64.zip"
scripts/make-dmg.sh app/build/CAMR.app "$out/CAMR-macos-arm64.dmg"
hdiutil verify -quiet "$out/CAMR-macos-arm64.dmg"

cp scripts/install.sh "$out/install.sh"
(cd "$out" && shasum -a 256 camr-macos-arm64.tar.gz CAMR-macos-arm64.zip CAMR-macos-arm64.dmg install.sh > SHA256SUMS)

gh release create "$tag" -R Satasdin/CAMR --target "$(git rev-parse HEAD)" --latest \
  --title "CAMR $version" \
  --notes "CAMR for Apple silicon: the app needs macOS 26, the camr program macOS 14.

Easiest, and the app opens without macOS's Open Anyway step: curl -fsSL https://github.com/Satasdin/CAMR/releases/latest/download/install.sh | sh -s -- --app

Or download CAMR-macos-arm64.dmg, open it and drag CAMR into Applications. CAMR isn't notarised by Apple, so the first time you open it macOS stops it: open System Settings › Privacy & Security and choose Open Anyway." \
  "$out/camr-macos-arm64.tar.gz" "$out/CAMR-macos-arm64.zip" "$out/CAMR-macos-arm64.dmg" "$out/install.sh" "$out/SHA256SUMS"
echo "published $tag"
