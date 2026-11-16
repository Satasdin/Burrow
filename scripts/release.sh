#!/bin/zsh
# Builds the terminal program and the desktop app and publishes them as a GitHub release.
#   scripts/release.sh v1.0.0
set -euo pipefail
cd "${0:A:h}/.."
version="${1:?usage: release.sh vX.Y.Z}"
tag="burrow-$version"
out="$(mktemp -d)"

swift build -c release --product burrow
cp .build/release/burrow "$out/burrow"
codesign --force --sign - "$out/burrow"
tar -czf "$out/burrow-macos-arm64.tar.gz" -C "$out" burrow

app/build.sh
# The zip is what install.sh --app fetches with curl; the DMG is the download for a browser, with the drag-to-Applications window.
ditto -c -k --sequesterRsrc --keepParent app/build/Burrow.app "$out/Burrow-macos-arm64.zip"
scripts/make-dmg.sh app/build/Burrow.app "$out/Burrow-macos-arm64.dmg"
hdiutil verify -quiet "$out/Burrow-macos-arm64.dmg"

cp scripts/install.sh "$out/install.sh"
(cd "$out" && shasum -a 256 burrow-macos-arm64.tar.gz Burrow-macos-arm64.zip Burrow-macos-arm64.dmg install.sh > SHA256SUMS)

gh release create "$tag" -R Satasdin/Burrow --target "$(git rev-parse HEAD)" --latest \
  --title "Burrow $version" \
  --notes "Burrow for Apple silicon: the app needs macOS 26, the burrow program macOS 14.

Easiest, and the app opens without macOS's Open Anyway step: curl -fsSL https://github.com/Satasdin/Burrow/releases/latest/download/install.sh | sh -s -- --app

Or download Burrow-macos-arm64.dmg, open it and drag Burrow into Applications. Burrow isn't notarised by Apple, so the first time you open it macOS stops it: open System Settings › Privacy & Security and choose Open Anyway." \
  "$out/burrow-macos-arm64.tar.gz" "$out/Burrow-macos-arm64.zip" "$out/Burrow-macos-arm64.dmg" "$out/install.sh" "$out/SHA256SUMS"
echo "published $tag"
