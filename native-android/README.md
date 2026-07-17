# PlexiBeer — app Android native (parité iOS)

Application **Kotlin + Jetpack Compose**, miroir de `native-ios/` + **mode invité WAN**.

## Expérience cible

### Compte maison (owner)
- Login + session cookie persistée (`beer_session`)
- TLS LAN (`192.168.1.50:8444`) avec policy domaine (Let’s Encrypt) **ou VPN**
- Wizard, historique, wishlist, idées cadeaux, offline queue…

### Invité (4G/5G, sans VPN)
- Onglet **Invitation** → coller le lien `…/beer/join/…` (ou deep link)
- `POST /api/native/join` → Bearer device-bound
- Base URL WAN forcée (`eiter.freeboxos.fr`, IPv4 prefer)
- Historique + check-ins perso uniquement (pas wishlist / cadeaux / admin)
- **Pas de bouton Déconnexion** (évite de perdre l’accès device-bound)

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

## Install

### Owner / couple
1. APK : `dist/PlexiBeer-debug.apk` ou `https://eiter.freeboxos.fr/mobile/beer/PlexiBeer.apk`
2. Autoriser sources inconnues
3. Wi‑Fi maison ou VPN → login compte permanent

### Invité (4G/5G)
1. Même APK (lien public ci-dessus)
2. Ouvrir le lien d’invitation → copier dans l’app **Invitation** → Activer
3. Pas de Wi‑Fi Freebox ni VPN requis

## Réseau

| Mode | URL |
|------|-----|
| Owner (prioritaire) | `https://192.168.1.50:8444/beer/` |
| Owner (fallback) | `https://eiter.freeboxos.fr/beer/` |
| Invité | WAN FQDN uniquement (+ fallback IPv4) |

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
