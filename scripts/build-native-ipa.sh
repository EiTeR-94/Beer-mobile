#!/usr/bin/env bash
# Build IPA native — même logique que Xcode Archive, sans signature (AltStore re-signe)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${BEER_SERVER_URL:-}" ]]; then
  echo "BEER_SERVER_URL manquant" >&2
  exit 1
fi

node scripts/write-native-config.js

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen requis (brew install xcodegen)" >&2
  exit 1
fi

(cd native-ios && xcodegen generate)

DERIVED="$ROOT/build/DerivedData"
rm -rf "$ROOT/build/Payload" "$DERIVED"
mkdir -p "$ROOT/build"

echo "==> xcodebuild (Release iphoneos)"
xcodebuild \
  -project "$ROOT/native-ios/BeerNative.xcodeproj" \
  -scheme BeerNative \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM=""

APP="$(find "$DERIVED/Build/Products" -name "Plexi Beer.app" -type d | head -1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "Plexi Beer.app introuvable après build" >&2
  find "$DERIVED" -name "*.app" >&2 || true
  exit 1
fi

echo "==> IPA"
rm -rf "$ROOT/build/Payload"
mkdir -p "$ROOT/build/Payload"
cp -R "$APP" "$ROOT/build/Payload/"
rm -f "$ROOT/build/PlexiBeer.ipa"
(cd "$ROOT/build" && zip -qr PlexiBeer.ipa Payload)

echo "OK: $ROOT/build/PlexiBeer.ipa"
file "$ROOT/build/Payload/Plexi Beer.app/Plexi Beer" || ls -la "$ROOT/build/Payload/Plexi Beer.app/"