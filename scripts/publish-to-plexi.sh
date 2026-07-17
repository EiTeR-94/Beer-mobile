#!/usr/bin/env bash
# Publie IPA (+ icône optionnelle) sur le serveur Plexi — téléchargement direct BeerOff.ipa
# PAS d'AltStore, PAS d'altstore.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-$ROOT/build/BeerOff.ipa}"
DEST="${BEER_MOBILE_WEB_DIR:-/var/www/beer-mobile}"
ICON_SRC="${BEER_MOBILE_ICON:-/home/eiter/beer/app/static/icons/icon-180.png}"

if [[ ! -f "$IPA" ]]; then
  if [[ -f "$ROOT/build/PlexiBeer.ipa" ]]; then
    IPA="$ROOT/build/PlexiBeer.ipa"
  else
    echo "IPA introuvable: $IPA" >&2
    exit 1
  fi
fi

sudo install -d -m 755 -o www-data -g www-data "$DEST"
sudo install -m 644 -o www-data -g www-data "$IPA" "$DEST/BeerOff.ipa"
# Nettoie tout résidu AltStore
sudo rm -f "$DEST/altstore.json" "$DEST/.altstore-sha256"
if [[ -f "$ICON_SRC" ]]; then
  sudo install -m 644 -o www-data -g www-data "$ICON_SRC" "$DEST/icon-180.png"
fi

echo "Publié → $DEST/BeerOff.ipa"
echo "URL : https://eiter.freeboxos.fr/mobile/beer/BeerOff.ipa"
