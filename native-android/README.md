# PlexiBeer - Native Android App

Ceci est l'équivalent natif Android de l'application iOS BeerNative (fr.eiter.plexibeer).

**Owner only** : LAN/VPN uniquement. Pas de guest/invite/passkey (les invités utilisent la version web PWA).

## Structure
- Même logique que l'iOS (après clean) :
  - Owner : toujours le chemin LAN (`https://192.168.1.50:8444/beer/`)
  - Pas de mode 5G/invité dans le natif.

## Configuration
- applicationId: `fr.eiter.plexibeer`
- `ServerSettings.lanApiBase` = `https://192.168.1.50:8444/beer/` (hardcodé pour fiabilité)

## Tester l'APK - Le plus simple possible (Windows ou Linux)

**L'APK se récupère en 1 clic via GitHub Actions** (pas besoin de SDK ni Android Studio pour tester) :

1. Va sur le repo → **Actions** → "Build Android APK (PlexiBeer native)"
2. Prends le dernier run vert → artifact **plexibeer-debug-apk**
3. Télécharge `app-debug.apk` sur ton PC Windows.

### Option la plus simple sur WINDOWS (recommandée)

Utilise un émulateur léger tiers (beaucoup plus simple et rapide à installer que Android Studio complet) :

**Recommandé : LDPlayer ou MuMu Player** (léger, drag & drop APK facile, bon pour tester)

- **LDPlayer** (très simple) : https://www.ldplayer.net/
  - Télécharge l'installateur, installe, lance.
  - Glisse-dépose directement l'APK dans la fenêtre de l'émulateur, ou clique l'icône APK dans la barre latérale.
  - L'app apparaît dans le launcher Android.

- **MuMu Player** (souvent cité comme un des plus légers en 2026) : https://www.mumuplayer.com/
  - Même principe : install → lancer → installer APK via le menu ou drag & drop.

Une fois l'app lancée :
- Elle utilise par défaut `https://192.168.1.50:8444/beer/`
- Si ton Windows est sur le même LAN que le serveur → ça devrait marcher direct (l'émulateur hérite du réseau de Windows).
- Si besoin de tester via "localhost du host" (rare ici) : il y a des boutons dans l'app de test pour changer la base à la volée.

### Option officielle (plus lourde)

Si tu veux l'émulateur stock Google :
- Tu peux installer **seulement** les outils en ligne de commande Android (pas tout Android Studio).
- Ou utiliser l'émulateur intégré à Android Studio (mais c'est ce que tu trouvais chiant).

Dans l'émulateur officiel, pour joindre des services sur la machine hôte Windows : souvent `10.0.2.2` à la place de localhost. Ici comme c'est une IP LAN (192.168.1.50), teste d'abord avec l'IP réelle.

### Build local (si tu veux itérer)

```bash
cd native-android
./gradlew assembleDebug
# APK dans : app/build/outputs/apk/debug/app-debug.apk
```

## Build / dev
- CI GitHub build auto l'APK à chaque push sur `native-android/**` (le plus pratique pour tester vite).
- L'APK debug suffit pour valider le réseau owner + appels API.
- Pour dev UI complet plus tard : Android Studio.

## Parité iOS (en cours)

L'app Android est maintenant une vraie application Compose avec :
- Login owner
- Wizard "Nouveau" (nom, brasserie, style, note, commentaire, photo)
- Historique des checkins + photos
- Galerie
- Wishlist (ajout / suppression)

Même logique owner-only LAN/VPN que l'iOS.

Prochaines étapes rapides possibles : scanner code-barres ML Kit, upload photo complet, offline, etc.

L'APK produite par CI est utilisable pour ta copine.

## Réseau (owner only)
- Toujours LAN path : `https://192.168.1.50:8444/beer/`
- L'app native n'a pas de chemin invité 5G (PWA web pour les autres).
- Timeouts client un peu relax (comme sur iOS).

Désolé pour le conseil Waydroid précédent — j'avais le contexte du serveur Debian en tête. Sur Windows, LDPlayer ou MuMu + artifact CI est le chemin le moins chiant. 

J'ai ajouté dans le stub (MainActivity) :
- Boutons presets LAN / 10.0.2.2
- Champ texte pour coller n'importe quelle base
- Tout ça change la base **à chaud** sans re-build.

L'UI de test dans l'APK permet de voir/changer la base facilement.
