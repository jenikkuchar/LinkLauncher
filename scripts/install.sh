#!/usr/bin/env bash
# Sestaví Release verzi LinkLauncheru a nainstaluje ji do /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="LinkLauncher"
DERIVED="$ROOT/build/DerivedData"
DEST="/Applications/$APP_NAME.app"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Chybí XcodeGen. Nainstalujte ho: brew install xcodegen" >&2
    exit 1
fi

echo "▸ Generuji Xcode projekt…"
xcodegen generate --quiet

echo "▸ Sestavuji Release…"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    build | (command -v xcpretty >/dev/null 2>&1 && xcpretty || cat)

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT" ]]; then
    echo "Build nenalezen: $BUILT" >&2
    exit 1
fi

if pgrep -x "$APP_NAME" >/dev/null; then
    echo "▸ Ukončuji běžící instanci…"
    osascript -e "tell application id \"cz.jenikkuchar.LinkLauncher\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.25
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
fi

echo "▸ Kopíruji do ${DEST}…"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

echo "▸ Spouštím…"
open "$DEST"
echo "✓ Hotovo. Launcher otevřete zkratkou ⌘⇧Space."
