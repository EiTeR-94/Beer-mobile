# Plexi Beer iOS — app NATIVE SwiftUI

**Ce n'est plus Capacitor.** L'IPA contient du code Swift/SwiftUI compilé :
- Scanner EAN natif (AVFoundation)
- UI 100 % native (pas de WebView, pas de HTML)
- File d'attente offline sur l'iPhone
- API Beer distante pour login, lookup, sync

**Coût : 0 €** — build sur Mac GitHub gratuit, install via AltStore.

---

## Secret GitHub

| Secret | Exemple |
|--------|---------|
| `BEER_SERVER_URL` | `https://ton-serveur.example:8444/beer` |

**Important : port `8444`** (TLS direct LAN/VPN). Le port `8443` utilise PROXY/sslh — incompatible avec l'app native.

Injecté dans `native-ios/Config/Build.xcconfig` au build.

---

## Build

1. **Actions** → **Build iOS IPA** → **Run workflow**
2. **Artifacts** → `PlexiBeer.ipa`
3. **AltStore** → installer

---

## Côté serveur Beer

```bash
cd /home/eiter/beer && docker compose up -d
```

`BEER_MOBILE_CORS=1` requis (déjà dans docker-compose).

---

## Offline

| Action | Hors ligne |
|--------|------------|
| Ouvrir l'app | Oui |
| Scanner EAN (caméra native) | Oui |
| Identifier bière (catalogue) | Non — réseau requis |
| Saisie manuelle + noter | Oui → file locale |
| Sync | Auto au retour Wi‑Fi/VPN |

---

## Structure

```
native-ios/
  BeerNative/Sources/   ← SwiftUI + API + offline
  project.yml           ← XcodeGen
```