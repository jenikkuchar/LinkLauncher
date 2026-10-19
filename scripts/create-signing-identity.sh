#!/usr/bin/env bash
# Jednorázově vytvoří v klíčence vlastní (self-signed) certifikát pro podepisování LinkLauncheru.
#
# Proč: ad-hoc podpis se mění s každým buildem a macOS pak bere novou verzi jako jinou aplikaci –
# zapomene udělená oprávnění (např. přístup k datům Chrome v Soukromí a zabezpečení).
# Se stálým certifikátem zůstává identita aplikace stejná. Nepotřebuje Apple Developer účet.
set -euo pipefail

cd "$(dirname "$0")"
source ./signing-identity.sh
NAME="$LINKLAUNCHER_SIGNING_NAME"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "$(linklauncher_signing_identity)" == "$NAME" ]]; then
    echo "✓ Certifikát „$NAME“ už v klíčence je."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="linklauncher-$RANDOM$RANDOM"

cat > "$TMP/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

echo "▸ Vytvářím certifikát „$NAME“ (platnost 10 let)…"
# Systémový /usr/bin/openssl (LibreSSL) vytváří .p12, který klíčenka umí importovat.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS"

echo "▸ Importuji do přihlašovací klíčenky…"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "▸ Nastavuji důvěru pro podepisování kódu (macOS se zeptá na heslo)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if [[ "$(linklauncher_signing_identity)" == "$NAME" ]]; then
    echo "✓ Hotovo. scripts/install.sh a scripts/make-dmg.sh ho teď použijí automaticky."
    echo "  Po prvním buildu s novým podpisem je potřeba oprávnění udělit ještě jednou (pak už vydrží)."
else
    echo "Certifikát se nepodařilo ověřit pro podepisování – zkontrolujte ho v aplikaci Klíčenka." >&2
    exit 1
fi
