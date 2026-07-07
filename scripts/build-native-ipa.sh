#!/usr/bin/env bash
# Build IPA native — format AltStore (Payload/PlexiBeer.app, binaire signé ad-hoc)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export BEER_SERVER_URL="${BEER_SERVER_URL:-https://eiter.freeboxos.fr/beer}"

node scripts/write-native-config.js

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen requis (brew install xcodegen)" >&2
  exit 1
fi

(cd native-ios && xcodegen generate)

DERIVED="$ROOT/build/DerivedData"
rm -rf "$ROOT/build/Payload" "$DERIVED" "$ROOT/build/PlexiBeer.ipa"
mkdir -p "$ROOT/build"

echo "==> xcodebuild (Release iphoneos)"
set +e
xcodebuild \
  -project "$ROOT/native-ios/BeerNative.xcodeproj" \
  -scheme BeerNative \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  2>&1 | tee "$ROOT/build/xcodebuild.log"
XC=${PIPESTATUS[0]}
set -e
if [[ "$XC" -ne 0 ]]; then
  echo "::group::Swift compile errors"
  grep -E "error:" "$ROOT/build/xcodebuild.log" | tail -30 | while IFS= read -r line; do
    echo "$line"
    echo "::error::$line"
  done || true
  echo "::endgroup::"
  exit "$XC"
fi

APP="$(find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" -type d | head -1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  APP="$(find "$DERIVED/Build/Products" -name "*.app" -type d | head -1)"
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "::error::Aucun .app après build" >&2
  find "$DERIVED" -name "*.app" >&2 || true
  exit 1
fi

APP_NAME="$(basename "$APP")"
PLIST="$APP/Info.plist"
BIN_NAME="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$PLIST" 2>/dev/null || true)"

echo "==> Vérification bundle ($APP_NAME)"
if [[ -z "$BIN_NAME" || ! -f "$APP/$BIN_NAME" ]]; then
  echo "::error::Binaire manquant dans $APP" >&2
  ls -la "$APP" >&2
  exit 1
fi

if /usr/libexec/PlistBuddy -c Print "$PLIST" | grep -q '\$(' ; then
  echo "::error::Info.plist contient des variables non résolues" >&2
  /usr/libexec/PlistBuddy -c Print "$PLIST" >&2
  exit 1
fi

file "$APP/$BIN_NAME" | grep -q "Mach-O" || {
  echo "::error::Binaire Mach-O invalide" >&2
  file "$APP/$BIN_NAME" >&2
  exit 1
}

echo "==> Signature ad-hoc (AltStore re-signera)"
codesign --force --sign - --timestamp=none --deep "$APP" 2>/dev/null || \
  codesign --force --sign - --timestamp=none "$APP"

echo "==> IPA"
rm -rf "$ROOT/build/Payload"
mkdir -p "$ROOT/build/Payload"
ditto "$APP" "$ROOT/build/Payload/$APP_NAME"
(cd "$ROOT/build" && zip -qr PlexiBeer.ipa Payload)

echo "OK: $ROOT/build/PlexiBeer.ipa ($APP_NAME, exe=$BIN_NAME)"
unzip -l "$ROOT/build/PlexiBeer.ipa" | head -15