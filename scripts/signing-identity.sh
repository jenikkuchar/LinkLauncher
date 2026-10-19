#!/usr/bin/env bash
# Společná funkce pro build skripty: vrátí podpisovou identitu.
# Pokud existuje vlastní certifikát „LinkLauncher Local Signing“ (viz create-signing-identity.sh),
# použije se – podpis je pak stejný u každého buildu a macOS si pamatuje udělená oprávnění.
# Jinak se podepisuje ad-hoc („-“).

LINKLAUNCHER_SIGNING_NAME="LinkLauncher Local Signing"

linklauncher_signing_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$LINKLAUNCHER_SIGNING_NAME\""; then
        echo "$LINKLAUNCHER_SIGNING_NAME"
    else
        echo "-"
    fi
}
