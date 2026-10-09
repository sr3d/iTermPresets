#!/bin/bash
# Packages build/iTermPresets.app into dist/iTermPresets-<version>.dmg with an Applications shortcut.
# Run ./build-app.sh first. Usage: VERSION=1.2.0 ./make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
APP=build/iTermPresets.app
[[ -d "$APP" ]] || { echo "Missing $APP — run ./build-app.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/iTermPresets-$VERSION.dmg"
rm -f "$DMG"
# hdiutil intermittently fails with "Resource busy"; retry a few times.
for attempt in 1 2 3 4 5; do
    hdiutil create -volname "iTerm Presets $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null && break
    [[ $attempt == 5 ]] && exit 1
    sleep $((attempt * 2))
done
echo "Built $DMG"
