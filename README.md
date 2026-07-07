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

## Connexion 5G / "SSL refusé" (iOS)

En 5G l'iPhone préfère souvent l'IPv6. L'enregistrement AAAA Freebox (`eiter.freeboxos.fr`) pointe vers l'IPv6 du routeur mais le port 443 n'y est pas forwardé → connexion refusée → erreur "SSL refusé" dans l'app native (mappée depuis `secureConnectionFailed` / `serverCertificateUntrusted`).

**Solution dans l'app :** le chemin invités 5G utilise maintenant `PlexiIPv4URLProtocol` + `HomelabIPv4Transport` (force IPv4 direct + SNI correct vers 82.64.151.113). Même mécanisme que le contournement LAN.

Rebuild l'IPA après modif et réinstalle via AltStore.

Workarounds temporaires :
- WiFi maison (utilise IP LAN directe 192.168.1.50:8444)
- VPN Plexi activé en 5G
- Version web Safari : https://eiter.freeboxos.fr/beer/