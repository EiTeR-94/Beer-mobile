# Plexi Beer — app iOS native

**Projet Xcode Swift/SwiftUI.** Pas de Capacitor, pas de WebView, pas de HTML. **Pas d'AltStore.**

## Invités 4G/5G

1. Télécharger l'IPA : https://eiter.freeboxos.fr/mobile/beer/BeerOff.ipa
2. Installer (sideload / outil de ton choix)
3. Lien d'invitation → app → **Invitation** → coller → Activer
4. Bearer device-bound, WAN only, **pas de déconnexion**

Android : https://eiter.freeboxos.fr/mobile/beer/BeerOff.apk

```
native-ios/          ← ouvre avec Xcode (après xcodegen generate)
scripts/build-native-ipa.sh
```

## Build IPA (GitHub Actions)

1. Secret `BEER_SERVER_URL` = `https://ton-serveur/beer`
2. Actions → **Build iOS IPA** → Run
3. Artifact / Release → télécharger `BeerOff.ipa`

## Build local (Mac + Xcode)

```bash
export BEER_SERVER_URL="https://ton-serveur/beer"
brew install xcodegen
./scripts/build-native-ipa.sh
# ou : cd native-ios && xcodegen generate && open BeerNative.xcodeproj
```

## Connexion 5G / "SSL refusé" (iOS)

En 5G l'iPhone préfère souvent l'IPv6. L'enregistrement AAAA Freebox (`eiter.freeboxos.fr`) pointe vers l'IPv6 du routeur mais le port 443 n'y est pas forwardé → connexion refusée.

**Solution dans l'app :** invités 5G utilisent `PlexiIPv4URLProtocol` + `HomelabIPv4Transport` (force IPv4 + SNI).
