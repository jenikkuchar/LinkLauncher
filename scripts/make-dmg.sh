#!/usr/bin/env bash
# Sestaví Release verzi LinkLauncheru a zabalí ji do instalačního DMG
# (aplikace + odkaz na /Applications pro instalaci přetažením).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="LinkLauncher"
DERIVED="$ROOT/build/DerivedData"
OUT_DIR="$ROOT/build"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Chybí XcodeGen. Nainstalujte ho: brew install xcodegen" >&2
    exit 1
fi

echo "▸ Generuji Xcode projekt…"
xcodegen generate --quiet

source "$ROOT/scripts/signing-identity.sh"
IDENTITY="$(linklauncher_signing_identity)"
if [[ "$IDENTITY" == "-" ]]; then
    echo "ℹ︎ Podepisuji ad-hoc – macOS po každém buildu zapomene udělená oprávnění."
    echo "  Jednorázově to vyřeší: scripts/create-signing-identity.sh"
fi

echo "▸ Sestavuji Release (podpis: $IDENTITY)…"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    build | (command -v xcpretty >/dev/null 2>&1 && xcpretty || cat)

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
    echo "Build nenalezen: $APP" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "▸ Připravuji obsah DMG…"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "▸ Vytvářím ${DMG}…"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG" >/dev/null

echo "✓ Hotovo: $DMG"
echo "  Instalace: otevřete DMG a přetáhněte $APP_NAME do složky Aplikace."
echo "  Aplikace je podepsaná ad-hoc – na jiném Macu ji poprvé otevřete přes pravý klik → Otevřít."
