#!/usr/bin/env bash
# Publie IPA + altstore.json sur le serveur Plexi (MAJ AltStore).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-$ROOT/build/PlexiBeer.ipa}"
BUILD="${2:-}"
DEST="${BEER_MOBILE_WEB_DIR:-/var/www/beer-mobile}"
ICON_SRC="${BEER_MOBILE_ICON:-/home/eiter/beer/app/static/icons/icon-180.png}"

if [[ ! -f "$IPA" ]]; then
  echo "IPA introuvable: $IPA" >&2
  exit 1
fi

node "$ROOT/scripts/generate-altstore-source.js" "$IPA" "$BUILD"
ALTSTORE_OUT="${ALTSTORE_OUT_DIR:-$ROOT/dist}"

sudo install -d -m 755 -o www-data -g www-data "$DEST"
sudo install -m 644 -o www-data -g www-data "$IPA" "$DEST/PlexiBeer.ipa"
sudo install -m 644 -o www-data -g www-data "$ALTSTORE_OUT/altstore.json" "$DEST/altstore.json"
if [[ -f "$ICON_SRC" ]]; then
  sudo install -m 644 -o www-data -g www-data "$ICON_SRC" "$DEST/icon-180.png"
fi

echo "Publié → $DEST"
echo "Source AltStore : https://192.168.1.50:8444/mobile/beer/altstore.json"