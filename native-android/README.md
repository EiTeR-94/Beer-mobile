# PlexiBeer - Native Android App

Ceci est l'équivalent natif Android de l'application iOS BeerNative (fr.eiter.plexibeer).

## Structure
- Même logique que l'iOS :
  - Comptes locaux : chemin LAN (WiFi/VPN) via 192.168.1.50:8444 ou LAN
  - Invités : chemin 5G via domaine public + Passkeys (Credential Manager)

## Configuration
- applicationId: fr.eiter.plexibeer
- Utilise les mêmes bases que ServerSettings de l'iOS (adapté).

## Pour builder
1. Ouvrir le dossier `native-android` dans Android Studio.
2. Sync Gradle.
3. Run sur émulateur ou device.

## TODO pour full parité avec iOS
- Intégration Passkeys complète (Credential Manager + WebAuthn)
- Scanner code-barres avec ML Kit (comme BarcodeScannerView)
- Camera pour photos de verre
- Tous les sheets : History, Admin, Wishlist, Gallery, Gifts, etc.
- Offline cache et queue
- Thème et composants identiques

## Réseau
- Même gestion LAN vs WAN que dans les derniers fixes iOS.
- Local accounts toujours sur LAN path.

Basé sur le code iOS après les corrections pour la connexion locale et invités 5G.
