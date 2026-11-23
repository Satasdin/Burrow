#!/bin/zsh
# Builds CAMR.app into app/build.
set -euo pipefail
cd "${0:A:h}"
swift build -c release
bundle=build/CAMR.app
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/CAMR" "$bundle/Contents/MacOS/CAMR"
cp Info.plist "$bundle/Contents/Info.plist"
mkdir -p "$bundle/Contents/Resources"
cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
# The logo and its C (D-120, D-124).
cp Resources/Brand/* "$bundle/Contents/Resources/"
# The camr command rides inside the app, so the Programs page can point every program at a full path that exists.
(cd .. && swift build -c release --product camr)
mkdir -p "$bundle/Contents/Resources/bin"
cp "$(cd .. && swift build -c release --show-bin-path)/camr" "$bundle/Contents/Resources/bin/camr"
# Its name before the rename (D-124), for a program set up with it.
ln -s camr "$bundle/Contents/Resources/bin/burrow"
codesign --force --sign - "$bundle" >/dev/null
echo "built $PWD/$bundle"
