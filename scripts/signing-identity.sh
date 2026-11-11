#!/usr/bin/env bash
# Společná funkce pro build skripty: vrátí podpisovou identitu.
# Pokud existuje vlastní certifikát „LinkLauncher Local Signing“ (viz create-signing-identity.sh),
# použije se – podpis je pak stejný u každého buildu a macOS si pamatuje udělená oprávnění.
# Jinak se podepisuje ad-hoc („-“).

LINKLAUNCHER_SIGNING_NAME="LinkLauncher Local Signing"

# Přepodepíše hotovou aplikaci zvolenou identitou (u ad-hoc nic nedělá).
# Build běží vždy ad-hoc: kdyby se identita předala xcodebuildu, vztáhla by se i na balíčky
# (KeyboardShortcuts) a Xcode by po nich chtěl vývojářský tým.
linklauncher_resign() {
    local app="$1" identity="$2" entitlements="$3"
    [[ "$identity" == "-" ]] && return 0
    echo "▸ Podepisuji certifikátem „${identity}“…"
    codesign --force --deep --sign "$identity" --entitlements "$entitlements" "$app"
    codesign --verify --deep --strict "$app"
}

linklauncher_signing_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$LINKLAUNCHER_SIGNING_NAME\""; then
        echo "$LINKLAUNCHER_SIGNING_NAME"
    else
        echo "-"
    fi
}
