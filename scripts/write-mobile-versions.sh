#!/usr/bin/env bash
# Écrit /var/www/beer-mobile/versions.json (+ miroir portail) à partir des artefacts publiés.
set -euo pipefail

DEST="${BEER_MOBILE_WEB_DIR:-/var/www/beer-mobile}"
WEBAPP_VER_FILE="${BEER_VERSION_FILE:-/home/eiter/beer/VERSION}"
AAPT="${AAPT:-/home/eiter/Android/Sdk/build-tools/34.0.0/aapt}"

IOS_VER="?"
IOS_BUILD="?"
if [[ -f "$DEST/BeerOff.ipa" || -f "$DEST/beeroff.ipa" ]]; then
  IPA="$DEST/BeerOff.ipa"
  [[ -f "$IPA" ]] || IPA="$DEST/beeroff.ipa"
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

WEBAPP="?"
[[ -f "$WEBAPP_VER_FILE" ]] && WEBAPP=$(tr -d ' \n' < "$WEBAPP_VER_FILE")

# Europe/Paris — format lisible pour le portail
UPDATED=$(TZ=Europe/Paris date +"%d-%m-%Y %H:%M")
UPDATED_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP=$(mktemp)
python3 - "$TMP" "$IOS_VER" "$IOS_BUILD" "$AND_VER" "$AND_BUILD" "$WEBAPP" "$UPDATED" "$UPDATED_ISO" <<'PY'
import json, sys
path, ios, ib, andv, ab, web, updated, updated_iso = sys.argv[1:9]
doc = {
    "ios": ios,
    "ios_build": ib,
    "android": andv,
    "android_build": ab,
    "webapp": web,
    # Affichage humain (portail) : dd-MM-YYYY HH:mm (Europe/Paris)
    "updated_at": updated,
    "updated_at_iso": updated_iso,
    "portal_url": "https://eiter.freeboxos.fr/mobile/beer/",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(json.dumps(doc, ensure_ascii=False))
PY

sudo install -m 644 -o www-data -g www-data "$TMP" "$DEST/versions.json"
# miroir repo
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/web-portal"
cp -f "$TMP" "$ROOT/web-portal/versions.json"
rm -f "$TMP"
echo "versions.json → $DEST/versions.json (ios=$IOS_VER/$IOS_BUILD android=$AND_VER/$AND_BUILD web=$WEBAPP)"
