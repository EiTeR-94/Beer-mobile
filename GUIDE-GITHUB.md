# Plexi Beer iOS — build GitHub + AltStore

GitHub compile une **IPA non signée** (Mac gratuit, repo public). **AltStore** la re-signe sur ton PC à l’installation.

**Coût : 0 €**

---

## Secret GitHub (un seul obligatoire)

**Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret | Exemple | Rôle |
|--------|---------|------|
| `BEER_SERVER_URL` | `https://ton-serveur.example/beer/` | URL Beer (jamais dans le code public) |
| `BEER_ALLOW_NAVIGATION` | *(optionnel)* `10.0.0.1,10.0.0.2` | IPs LAN autorisées en plus du hostname |

Aucun secret Apple requis pour le build.

---

## Lancer le build

1. **Actions** → **Build iOS IPA** → **Run workflow**
2. Attends 10–25 min
3. **Artifacts** → **PlexiBeer-ipa** → `PlexiBeer.ipa`

---

## Installer (AltStore)

1. **AltServer** actif sur le PC
2. Copie `PlexiBeer.ipa` sur l’iPhone
3. **AltStore** → **My Apps** → **+** → choisis l’IPA
4. AltStore re-signe avec ton Apple ID

---

## Repo public — sécurité

- Le **code** est visible, **pas** les secrets GitHub
- Ne commite jamais d’URL perso, mail, UDID ou mot de passe dans le dépôt
- `capacitor.config.json` contient des placeholders ; l’URL réelle vient du secret

---

## Fichiers utiles

| Fichier | Rôle |
|---------|------|
| `.github/workflows/ios-ipa.yml` | Pipeline Mac GitHub |
| `fastlane/Fastfile` | Build IPA non signée |
| `scripts/patch-capacitor-url.js` | Injecte l’URL Beer depuis le secret |