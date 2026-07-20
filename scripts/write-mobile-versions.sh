#!/usr/bin/env bash
# Écrit /var/www/beer-mobile/versions.json (+ miroir portail) à partir des artefacts publiés.
# Dates IPA / APK séparées (mtime fichier) pour éviter la confusion quand seule l'IPA bouge.
set -euo pipefail

DEST="${BEER_MOBILE_WEB_DIR:-/var/www/beer-mobile}"
WEBAPP_VER_FILE="${BEER_VERSION_FILE:-/home/eiter/beer/VERSION}"
AAPT="${AAPT:-/home/eiter/Android/Sdk/build-tools/34.0.0/aapt}"

fmt_mtime() {
  local f="$1"
  if [[ -f "$f" ]]; then
    TZ=Europe/Paris date -d "@$(stat -c %Y "$f")" +"%d-%m-%Y %H:%M"
  else
    echo ""
  fi
}

IOS_VER="?"
IOS_BUILD="?"
IPA=""
if [[ -f "$DEST/BeerOff.ipa" ]]; then
  IPA="$DEST/BeerOff.ipa"
elif [[ -f "$DEST/beeroff.ipa" ]]; then
  IPA="$DEST/beeroff.ipa"
fi
if [[ -n "$IPA" ]]; then
  read -r IOS_VER IOS_BUILD < <(python3 - "$IPA" <<'PY'
import sys, zipfile, plistlib
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.endswith("Info.plist") and n.count("/") == 2 and "Payload" in n:
        p = plistlib.loads(z.read(n))
        print(p.get("CFBundleShortVersionString", "?"), p.get("CFBundleVersion", "?"))
        break
else:
    print("? ?")
PY
)
fi
IOS_UPDATED=$(fmt_mtime "${IPA:-}")

AND_VER="?"
AND_BUILD="?"
APK=""
for c in "$DEST/BeerOff.apk" "$DEST/beeroff.apk"; do
  [[ -f "$c" ]] && APK="$c" && break
done
if [[ -n "$APK" && -x "$AAPT" ]]; then
  line=$("$AAPT" dump badging "$APK" 2>/dev/null | head -1 || true)
  AND_VER=$(echo "$line" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
  AND_BUILD=$(echo "$line" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
  AND_VER=${AND_VER:-?}
  AND_BUILD=${AND_BUILD:-?}
fi
AND_UPDATED=$(fmt_mtime "${APK:-}")

WEBAPP="?"
[[ -f "$WEBAPP_VER_FILE" ]] && WEBAPP=$(tr -d ' \n' < "$WEBAPP_VER_FILE")
WEB_UPDATED=$(fmt_mtime "$WEBAPP_VER_FILE")

# Date de génération du manifeste (pas « dernière maj app »)
GENERATED=$(TZ=Europe/Paris date +"%d-%m-%Y %H:%M")
GENERATED_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TMP=$(mktemp)
python3 - "$TMP" \
  "$IOS_VER" "$IOS_BUILD" "$IOS_UPDATED" \
  "$AND_VER" "$AND_BUILD" "$AND_UPDATED" \
  "$WEBAPP" "$WEB_UPDATED" \
  "$GENERATED" "$GENERATED_ISO" <<'PY'
import json, sys
(
    path,
    ios, ib, ios_upd,
    andv, ab, and_upd,
    web, web_upd,
    generated, generated_iso,
) = sys.argv[1:12]

doc = {
    "ios": ios,
    "ios_build": ib,
    "ios_updated_at": ios_upd or None,
    "android": andv,
    "android_build": ab,
    "android_updated_at": and_upd or None,
    "webapp": web,
    "webapp_updated_at": web_upd or None,
    # Génération du JSON (pas la date d’une plateforme)
    "manifest_generated_at": generated,
    "updated_at": generated,  # rétrocompat affichage
    "updated_at_iso": generated_iso,
    "portal_url": "https://eiter.freeboxos.fr/mobile/beer/",
    "note": "L’IPA et l’APK ont des cycles de maj séparés. Compare la version de ta plateforme.",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(json.dumps(doc, ensure_ascii=False))
PY

sudo install -m 644 -o www-data -g www-data "$TMP" "$DEST/versions.json"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/web-portal"
cp -f "$TMP" "$ROOT/web-portal/versions.json"
rm -f "$TMP"
echo "versions.json → $DEST/versions.json"
echo "  IPA  $IOS_VER ($IOS_BUILD) · maj $IOS_UPDATED"
echo "  APK  $AND_VER ($AND_BUILD) · maj $AND_UPDATED"
echo "  Web  $WEBAPP · maj $WEB_UPDATED"
