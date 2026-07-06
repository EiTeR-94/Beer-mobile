# Plexi Beer iOS — build gratuit avec GitHub Actions

Pas de MacinCloud : GitHub compile l’app sur un **Mac gratuit** et tu récupères le **`.ipa`** pour AltStore.

**Coût : 0 €** (repo **public** recommandé = minutes macOS illimitées).

---

## Avant de commencer (15 min)

### 1. Compte GitHub

Crée un compte sur https://github.com si besoin.

### 2. Mot de passe spécifique Apple (obligatoire)

1. https://appleid.apple.com → **Connexion et sécurité**
2. **Mots de passe pour app** → **Générer**
3. Nom : `GitHub Plexi Beer`
4. **Copie le mot de passe** (format `xxxx-xxxx-xxxx-xxxx`) — il ne s’affiche qu’une fois

### 3. Team ID Apple (10 caractères)

1. https://developer.apple.com/account (connecte-toi avec le **même Apple ID** qu’AltStore)
2. Accepte les conditions si demandé (compte développeur **gratuit**)
3. Note le **Team ID** (ex. `AB12C3D4EF`) — section adhésion / Membership

### 4. UDID de ton iPhone

Sur **Windows** (iTunes ou 3uTools) :

- Branche l’iPhone → clique sur le **numéro de série** → copie l’**UDID**

(C’est le même iPhone que pour AltStore.)

---

## Étape 1 — Créer le dépôt GitHub

1. GitHub → **New repository**
2. Nom : `plexi-beer-mobile` (ou autre)
3. **Public** (important pour macOS gratuit illimité)
4. Ne coche pas « Add README » (on pousse le dossier déjà prêt)

---

## Étape 2 — Envoyer le projet depuis le serveur (ou ton PC)

### Depuis le serveur Plexi

```bash
cd /home/eiter/beer-mobile
git init
git add .
git commit -m "Plexi Beer iOS — Capacitor + GitHub Actions"
git branch -M main
git remote add origin https://github.com/TON_COMPTE/plexi-beer-mobile.git
git push -u origin main
```

(Remplace `TON_COMPTE` ; GitHub demandera login — **Personal Access Token** si mot de passe refusé.)

### Depuis Windows

1. Copie le dossier `beer-mobile` ou l’archive `beer-mobile-phase1.tar.gz`
2. GitHub Desktop ou :

```bash
git init
git add .
git commit -m "initial"
git remote add origin https://github.com/TON_COMPTE/plexi-beer-mobile.git
git push -u origin main
```

---

## Étape 3 — Secrets GitHub

Dépôt → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Nom du secret | Valeur |
|---------------|--------|
| `APPLE_ID` | Ton e-mail Apple ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | Mot de passe spécifique (étape 2) |
| `APPLE_TEAM_ID` | Team ID 10 caractères |
| `IOS_DEVICE_UDID` | UDID iPhone |
| `KEYCHAIN_PASSWORD` | *(optionnel)* un mot de passe quelconque, ex. `PlexiBeer2026` |

---

## Étape 4 — Lancer le build

1. Onglet **Actions** du dépôt
2. **Build iOS IPA** (barre gauche)
3. **Run workflow** → **Run workflow**
4. Attends **10–25 min** (première fois plus long)

### Si ça échoue

- **register_devices** : connecte-toi une fois sur developer.apple.com et accepte les accords
- **2FA** : utilise bien le **mot de passe spécifique**, pas ton mot de passe iCloud
- **Team ID** incorrect : revérifie sur developer.apple.com
- Copie le **log rouge** de l’étape Fastlane pour debug

---

## Étape 5 — Télécharger le .ipa

1. Workflow terminé en **vert**
2. Tout en bas : **Artifacts** → **PlexiBeer-ipa**
3. Télécharge le zip → dedans : **`PlexiBeer.ipa`**

---

## Étape 6 — Installer avec AltStore (déjà fait chez toi)

1. Mets `PlexiBeer.ipa` sur l’iPhone (Fichiers, iCloud, mail…)
2. **AltStore** → **My Apps** → **+**
3. Choisis le `.ipa`
4. Ouvre **Plexi Beer** (Wi‑Fi maison ou VPN Plexi)

---

## Rebuild plus tard

Changement d’URL Beer ou de version → modifie le code → `git push` → **Run workflow** à nouveau → nouveau `.ipa` dans Artifacts.

Pas besoin de MacinCloud.

---

## Sécurité

- Les secrets restent **chiffrés** côté GitHub (Actions uniquement)
- Repo **public** : le **code** est visible, **pas** les secrets
- Ne commite **jamais** mots de passe dans le dépôt

---

## Fichiers utiles

| Fichier | Rôle |
|---------|------|
| `.github/workflows/ios-ipa.yml` | Pipeline Mac GitHub |
| `fastlane/Fastfile` | Signature + export IPA |
| `capacitor.config.json` | URL Beer distante |