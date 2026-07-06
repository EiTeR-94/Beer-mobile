# Plexi Beer — app iOS native

**Projet Xcode Swift/SwiftUI.** Pas de Capacitor, pas de WebView, pas de HTML.

```
native-ios/          ← ouvre avec Xcode (après xcodegen generate)
scripts/build-native-ipa.sh
```

## Build IPA (GitHub Actions)

1. Secret `BEER_SERVER_URL` = `https://ton-serveur/beer`
2. Actions → **Build iOS IPA** → Run
3. Artifact → AltStore

## Build local (Mac + Xcode)

```bash
export BEER_SERVER_URL="https://ton-serveur/beer"
brew install xcodegen
./scripts/build-native-ipa.sh
# ou : cd native-ios && xcodegen generate && open BeerNative.xcodeproj
```

L'ancien prototype Capacitor est dans `_archive/capacitor/` (abandonné).