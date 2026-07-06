# Plexi Beer — iOS phase 1 (Capacitor + AltStore)

App **personnelle** : coque iOS qui ouvre ton Beer Log sur le serveur (comme Safari, mais icône dédiée + plein écran).

**Coût visé :** ~4 $ MacinCloud (1 jour) + 0 € Apple ID. Pas de compte Developer 99 € pour l’instant.

---

## Ce qui est déjà prêt (serveur .50)

Dossier : `/home/eiter/beer-mobile/`

- `capacitor.config.json` → pointe vers `https://eiter.freeboxos.fr:8443/beer/`
- Icônes copiées depuis Beer
- Pas besoin de recopier tout le front : l’app charge le site en ligne (mises à jour Beer automatiques)

---

## Vue d’ensemble (3 étapes)

```
1. PC Windows     → AltServer + AltStore sur l’iPhone (une fois)
2. MacinCloud     → Builder le .ipa signé (une journée ~4 $)
3. iPhone         → Installer Plexi Beer via AltStore
```

Re-sign automatique ~tous les 7 jours via AltStore (PC Windows allumé sur le même Wi‑Fi).

---

## Étape A — Récupérer le projet sur ton PC Windows

### Option 1 — Depuis le serveur (SCP / WinSCP)

1. Sur le serveur, crée une archive :
   ```bash
   cd /home/eiter && tar czf beer-mobile-phase1.tar.gz beer-mobile/
   ```
2. Copie `beer-mobile-phase1.tar.gz` sur Windows (WinSCP, `scp`, clé USB…).
3. Décompresse dans `C:\Users\Toi\plexi\beer-mobile\`

### Option 2 — Clé USB / partage réseau

Copie le dossier `beer-mobile` tel quel.

---

## Étape B — AltStore sur Windows (faire AVANT ou APRÈS le build Mac)

> AltStore permet d’installer l’app sans TestFlight. Gratuit avec ton Apple ID.

### B1. Prérequis Windows

1. **iTunes** (Microsoft Store ou apple.com/itunes/win64) — pour le pilote iPhone
2. **iCloud pour Windows** (Microsoft Store) — requis par AltServer
3. iPhone et PC sur le **même Wi‑Fi** que la box

### B2. Installation

1. Télécharge **AltServer** : https://altstore.io — section Windows
2. Lance **AltServer** (icône dans la barre des tâches, près de l’horloge)
3. Branche l’iPhone en **USB** (première fois)
4. Clic droit AltServer → **Install AltStore** → choisis ton iPhone
5. Entre ton **Apple ID** (compte iCloud perso)
6. Sur l’iPhone : Réglages → Général → VPN et gestion des appareils → **faire confiance** au profil développeur

### B3. Garder AltStore actif

- AltServer doit tourner sur le PC de temps en temps (idéalement en tâche de fond)
- iPhone sur le **même réseau** → AltStore **re-signe seul** avant expiration (7 j)
- Limite compte gratuit : **3 apps** max (AltStore = 1, Plexi Beer = 2)

---

## Étape C — MacinCloud (builder l’app, ~4 $ / jour)

### C1. Louer le Mac

1. https://www.macincloud.com → **Pay as You Go** → **Pay by the Day** (~4 $)
2. Choisis macOS **Sonoma** ou **Sequoia**, Xcode préinstallé
3. Connecte-toi (Bureau à distance / VNC selon leur doc)

### C2. Transférer le projet

- Upload `beer-mobile-phase1.tar.gz` (navigateur, Dropbox, ou `scp` depuis Windows)
- Décompresse sur le Mac :
  ```bash
  tar xzf beer-mobile-phase1.tar.gz && cd beer-mobile
  ```

### C3. UDID de ton iPhone (important)

Sur **Windows** (iTunes) ou **MacinCloud** (Finder si USB impossible → méthode Windows) :

1. Branche l’iPhone
2. Récupère l’**UDID** :
   - iTunes : clic sur le numéro de série → UDID copiable
   - Ou app **iMazing** / **3uTools** sur Windows
3. Note l’UDID (format longue chaîne hex)

Sur MacinCloud dans **Xcode** (plus tard) : ton Apple ID enregistrera l’appareil automatiquement si tu branches via USB sur un Mac physique — sur MacinCloud distant, **ajoute l’UDID manuellement** :

- Xcode → Settings → Accounts → ton Apple ID → **Manage Certificates** / Devices  
- Ou https://developer.apple.com/account/resources/devices/list (compte gratuit « Personal Team » limité)

### C4. Build Capacitor + iOS

Dans le terminal MacinCloud :

```bash
cd ~/beer-mobile   # ou où tu as décompressé

# Node (souvent déjà là ; sinon brew install node)
node -v && npm -v

npm install
npx cap add ios
npm run icons
node scripts/patch-ios-plist.js
npx cap sync ios
npx cap open ios
```

Xcode s’ouvre.

### C5. Signature dans Xcode

1. Projet **App** (colonne gauche) → **Signing & Capabilities**
2. **Team** : ton nom (Personal Team — compte Apple ID gratuit)
3. **Bundle Identifier** : laisse `fr.eiter.plexibeer` (ou change si conflit)
4. Coche **Automatically manage signing**
5. Branche **Signing Certificate** : Apple Development

Si erreur « device not registered » : ajoute l’UDID (étape C3).

### C6. Vérifier l’URL Beer

Dans `capacitor.config.json` sur le Mac :

```json
"url": "https://eiter.freeboxos.fr:8443/beer/"
```

- Chez toi en Wi‑Fi : ça doit répondre dans Safari iPhone **avant** de tester l’app
- Hors maison : **VPN Plexi** obligatoire (comme aujourd’hui)
- Si ton URL habituelle est sans `:8443`, adapte (ex. hub `http://192.168.1.44:19998/beer/` → HTTPS de préférence)

### C7. Exporter le fichier .ipa pour AltStore

1. Xcode → menu **Product** → **Archive** (choisis « Any iOS Device », pas simulateur)
2. À la fin → **Distribute App**
3. **Development** (compte gratuit) ou **Custom** → exporte un **.ipa**
4. Télécharge le `.ipa` sur ton **PC Windows** (cloud, e-mail, USB…)

Nom suggéré : `PlexiBeer.ipa`

---

## Étape D — Installer Plexi Beer avec AltStore

1. Copie `PlexiBeer.ipa` sur l’iPhone :
   - **Fichiers** / iCloud Drive, ou AirDrop depuis Windows si dispo, ou mail à toi-même
2. Ouvre **AltStore** sur l’iPhone
3. Onglet **My Apps** → **+** → choisis `PlexiBeer.ipa`
4. L’app **Plexi Beer** apparaît sur l’écran d’accueil

### Premier lancement

1. Wi‑Fi maison **ou** VPN Plexi actif
2. Ouvre **Plexi Beer**
3. Connecte-toi (même login que le site web)
4. Teste un scan EAN

---

## Re-sign tous les ~7 jours

- Laisse **AltServer** tourner sur le PC Windows
- iPhone sur le même Wi‑Fi → AltStore rafraîchit en arrière-plan
- Notification AltStore si action manuelle nécessaire : ouvre AltStore → **Refresh All**

Pas besoin de repayer MacinCloud chaque semaine si AltStore est bien configuré.

---

## Dépannage rapide

| Problème | Piste |
|----------|--------|
| Écran blanc dans l’app | Safari iPhone ouvre la même URL ? VPN ? |
| « Unable to install » AltStore | Faire confiance au profil développeur (Réglages) |
| 3 apps max atteint | Supprime une app sideload inutile dans AltStore |
| Session Beer expirée | Reconnecte-toi (normal, comme le web) |
| Build Xcode échoue | Vérifie Team + UDID + Bundle ID unique |

---

## Plus tard — TestFlight (99 €/an)

Quand tu voudras : compte Apple Developer → même projet → Archive → Upload App Store Connect → TestFlight. Le dossier `beer-mobile` reste valable.

---

## Sécurité (inchangée)

- L’app **ne contient aucun mot de passe** ni secret serveur
- Accès réseau : LAN/VPN + login Beer (comme le site)
- Ne pas ouvrir Beer au WAN public pour « simplifier » l’app

---

## Aide depuis le serveur Plexi

Archive à jour :

```bash
cd /home/eiter && tar czf beer-mobile-phase1.tar.gz beer-mobile/
ls -lh beer-mobile-phase1.tar.gz
```