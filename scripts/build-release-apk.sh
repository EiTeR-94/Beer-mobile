#!/usr/bin/env bash
# Build APK release signée (keystore dist) + vérif empreinte.
# Usage:
#   ./scripts/build-release-apk.sh           # → dist/BeerOff.apk
#   ./scripts/build-release-apk.sh --publish # + /var/www/beer-mobile/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$ROOT/native-android"
DIST="$ROOT/dist"
AAPT="${AAPT:-/home/eiter/Android/Sdk/build-tools/34.0.0/aapt}"
APKSIGNER="${APKSIGNER:-/home/eiter/Android/Sdk/build-tools/34.0.0/apksigner}"
EXPECTED_SHA256="${BEER_CERT_SHA256:-9a75e75f8491500f8090095360f05d928d3c83f4c6ace2885c1c093e8a42a6ff}"
PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

# Load secrets if present and env not already set
if [[ -z "${BEER_KEYSTORE_FILE:-}" && -r /etc/plexi/secrets/plexi-beer-release.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /etc/plexi/secrets/plexi-beer-release.env
  set +a
fi

if [[ -z "${BEER_KEYSTORE_FILE:-}" || ! -f "${BEER_KEYSTORE_FILE}" ]]; then
  echo "ERROR: BEER_KEYSTORE_FILE manquant ou fichier absent." >&2
  echo "  source /etc/plexi/secrets/plexi-beer-release.env" >&2
  exit 1
fi
if [[ -z "${BEER_KEYSTORE_PASSWORD:-}" || -z "${BEER_KEY_ALIAS:-}" ]]; then
  echo "ERROR: BEER_KEYSTORE_PASSWORD / BEER_KEY_ALIAS manquants." >&2
  exit 1
fi
export BEER_KEY_PASSWORD="${BEER_KEY_PASSWORD:-$BEER_KEYSTORE_PASSWORD}"
export BEER_KEYSTORE_FILE BEER_KEYSTORE_PASSWORD BEER_KEY_ALIAS BEER_KEY_PASSWORD

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
  export JAVA_HOME
fi

echo "[build-release-apk] keystore=$BEER_KEYSTORE_FILE alias=$BEER_KEY_ALIAS"
echo "[build-release-apk] JAVA_HOME=$JAVA_HOME"
cd "$ANDROID"
./gradlew assembleRelease --stacktrace -x test

SRC="$ANDROID/app/build/outputs/apk/release/app-release.apk"
if [[ ! -f "$SRC" ]]; then
  # AGP sometimes names with unsigned when signing failed
  echo "ERROR: APK release introuvable: $SRC" >&2
  ls -la "$ANDROID/app/build/outputs/apk/release/" 2>/dev/null || true
  exit 1
fi

mkdir -p "$DIST"
OUT="$DIST/BeerOff.apk"
cp -f "$SRC" "$OUT"
# versioned copy for archive
if [[ -x "$AAPT" ]]; then
  line=$("$AAPT" dump badging "$OUT" 2>/dev/null | head -1 || true)
  VNAME=$(echo "$line" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
  VCODE=$(echo "$line" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
  if [[ -n "$VNAME" ]]; then
    cp -f "$OUT" "$DIST/BeerOff-${VNAME}-dist.apk"
  fi
else
  VNAME="?"
  VCODE="?"
fi

echo "[build-release-apk] verify signature…"
VERIFY=$("$APKSIGNER" verify --print-certs -v "$OUT" 2>&1) || {
  echo "$VERIFY" >&2
  echo "ERROR: apksigner verify failed" >&2
  exit 1
}
echo "$VERIFY" | head -25

GOT=$(echo "$VERIFY" | sed -n 's/.*SHA-256 digest: //p' | head -1 | tr -d ' :' | tr '[:upper:]' '[:lower:]')
if [[ -z "$GOT" ]]; then
  echo "ERROR: impossible d'extraire SHA-256 du certificat" >&2
  exit 1
fi
if [[ "$GOT" != "$EXPECTED_SHA256" ]]; then
  echo "ERROR: empreinte SHA-256 incorrecte" >&2
  echo "  attendu: $EXPECTED_SHA256" >&2
  echo "  obtenu:  $GOT" >&2
  echo "  → refuse publication (mauvais keystore)" >&2
  exit 1
fi

# Refuse Android Debug
if echo "$VERIFY" | grep -qi 'CN=Android Debug'; then
  echo "ERROR: APK signée Android Debug — interdit pour dist" >&2
  exit 1
fi

echo "[build-release-apk] OK $OUT"
echo "  package fr.eiter.plexibeer  versionName=$VNAME  versionCode=$VCODE"
echo "  cert SHA-256=$GOT"

if [[ "$PUBLISH" -eq 1 ]]; then
  DEST="${BEER_MOBILE_WEB_DIR:-/var/www/beer-mobile}"
  echo "[build-release-apk] publish → $DEST/"
  sudo install -m 644 -o www-data -g www-data "$OUT" "$DEST/BeerOff.apk"
  sudo install -m 644 -o www-data -g www-data "$OUT" "$DEST/beeroff.apk" 2>/dev/null || true
  sudo install -m 644 -o www-data -g www-data "$OUT" "$DEST/beerBeta.apk" 2>/dev/null || true
  sha256sum "$OUT" | awk '{print $1}' | sudo tee "$DEST/.apk-sha256" >/dev/null
  sudo chown www-data:www-data "$DEST/.apk-sha256" 2>/dev/null || true
  if [[ -x "$ROOT/scripts/write-mobile-versions.sh" ]]; then
    "$ROOT/scripts/write-mobile-versions.sh"
  fi
  echo "[build-release-apk] publié: https://eiter.freeboxos.fr/mobile/beer/BeerOff.apk"
fi
