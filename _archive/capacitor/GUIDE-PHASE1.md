# Plexi Beer — iOS (Capacitor + AltStore)

App **personnelle** : coque iOS qui ouvre Beer Log sur ton serveur (icône dédiée + plein écran).

---

## Principe

- Le front Beer reste sur le **serveur** (mises à jour automatiques)
- GitHub build une **IPA non signée**
- **AltStore** re-signe sur ton PC Windows

Voir **GUIDE-GITHUB.md** pour le workflow actuel.

---

## AltStore (Windows)

1. iTunes + iCloud pour Windows
2. **AltServer** + **AltStore** sur l’iPhone (USB, même Wi‑Fi)
3. Re-sign ~tous les 7 jours (AltServer actif sur le PC)

---

## URL Beer

Configure `BEER_SERVER_URL` en secret GitHub — pas dans le code versionné.

---

## Sécurité

- Aucun mot de passe serveur dans l’app
- Auth Beer = celle du site web (session navigateur)