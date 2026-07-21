# Signature APK Plexi Beer (distribution)

## Objectif

Toutes les APK publiées (`BeerOff.apk`) sont signées avec **le même keystore de distribution**.
Sans ça, Android refuse la mise à jour (« Application non installée ») et l’invité doit
désinstaller → perte du Bearer / `device_id` local.

## Source de vérité (pas de GitHub pour l’APK)

| Artefact | Source |
|----------|--------|
| **APK** | Build **local** sur `.50` avec keystore dist |
| **IPA** | GitHub Releases → `beer-mobile-sync` (timer) |

```bash
cd ~/beer-mobile
./scripts/build-release-apk.sh --publish
# → /var/www/beer-mobile/BeerOff.apk
```

Le timer `beer-mobile-sync` **ne tire plus l’APK** depuis GitHub (évite les signatures CI debug).
Option rare : `BEER_MOBILE_SYNC_APK=1` (toujours bloqué si cert ≠ dist).

## Empreinte attendue (non secret)

| Algo | Digest |
|------|--------|
| SHA-256 | `9a75e75f8491500f8090095360f05d928d3c83f4c6ace2885c1c093e8a42a6ff` |
| SHA-1 | `83062609396b6b26963a7e469b4b95d32909225d` |
| Alias | `plexi-beer` |
| Package | `fr.eiter.plexibeer` |

```bash
apksigner verify --print-certs /var/www/beer-mobile/BeerOff.apk
# SHA-256 digest doit matcher la table ci-dessus
```

## Secrets (serveur)

| Fichier | Rôle |
|---------|------|
| `/etc/plexi/secrets/plexi-beer-release.keystore` | PKCS12 (640 root:eiter) |
| `/etc/plexi/secrets/plexi-beer-release.env` | mots de passe + alias |

Inclus automatiquement dans le vault DR (`secrets-vault.sh` copie `/etc/plexi/secrets`).

```bash
set -a
# shellcheck disable=SC1091
source /etc/plexi/secrets/plexi-beer-release.env
set +a
./scripts/build-release-apk.sh --publish
```

## Maintenance automatisée

| Timer | Rôle |
|-------|------|
| `plexi-daily-maintenance` | `plexi-beer-mobile-health.sh` — keystore + cert APK + IPA |
| `plexi-weekly-maintenance` | même check (alerte Telegram si KO) |
| `secrets-vault-if-stale` (daily) | régénère vault si keystore plus récent |
| `beer-mobile-sync` | **IPA seulement** depuis GitHub |

Santé manuelle :

```bash
/home/eiter/scripts/plexi-beer-mobile-health.sh
```

## Règles

1. **Ne jamais régénérer** le keystore si des invités ont déjà l’APK signée avec.
2. **Ne jamais commit** keystore / `.env` / `keystore.properties`.
3. Backup vault / hors site du keystore + env (comme les autres secrets plexi).
4. `versionCode` strictement croissant à chaque publication.
5. Première APK dist : **4.4.21 / versionCode 230** — les invités Android réinstallent **une fois**, puis updates in-place.

## Migration 2026-07-20

Anciennes APK = signature **Android Debug**. Nouvelle dist = keystore **plexi-beer**.
Incompatible en update → 1 désinstall + reissue invite admin, puis plus jamais.
