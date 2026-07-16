# PlexiBeer — app Android native (parité iOS)

Application **Kotlin + Jetpack Compose**, owner-only (LAN/VPN), miroir de `native-ios/`.

## Expérience cible

Même parcours couple que l’IPA iOS :

- Login + session cookie persistée (`beer_session`)
- TLS LAN (`192.168.1.50:8444`) avec policy domaine (Let’s Encrypt)
- Wizard 3 étapes : scan/photo EAN · Untappd · manuel → photo → note/goûts/houblons
- Doublon « Déjà dégustée → Noter à nouveau »
- Historique (filtres, détail, edit, delete, re-noter)
- Galerie photos authentifiées
- Wishlist + **Goûter**
- Idées cadeaux (stats couple)
- Offline queue + sync + feuille « En attente »
- Barre réseau + toasts + thème sombre iOS

## Build local

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64   # ou 17
# Android SDK dans local.properties (sdk.dir=...)
cd native-android
./gradlew assembleDebug
# APK : app/build/outputs/apk/debug/app-debug.apk
```

## CI GitHub

Actions → **Build Android APK (PlexiBeer native)** → artifact `plexibeer-debug-apk`.

## Install (copine)

1. Télécharger `app-debug.apk` (ou `dist/PlexiBeer-debug.apk`)
2. Autoriser install depuis source inconnue
3. Ouvrir l’app **sur le Wi‑Fi maison** (ou VPN Plexi)
4. Se connecter avec **son** compte Beer

## Réseau

| Chemin | URL |
|--------|-----|
| Prioritaire | `https://192.168.1.50:8444/beer/` |
| Fallback | `https://eiter.freeboxos.fr/beer/` |

Pas de mode invité 5G dans le natif (PWA web pour les invités).

## Structure

```
app/src/main/java/fr/eiter/plexibeer/
  BeerAPI.kt          # API + multipart + assets
  HomelabTls.kt       # TLS LAN
  SessionStore.kt     # cookies persistés
  OfflineQueue.kt     # file offline
  AppViewModel.kt     # session / réseau / save
  ui/BeerApp.kt       # écrans + wizard + sheets
  ui/Components.kt
  ui/theme/Theme.kt   # palette iOS
```
