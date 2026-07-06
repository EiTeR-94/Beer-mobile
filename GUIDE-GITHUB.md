# Plexi Beer iOS — vraie app embarquée

L’IPA contient **le front Beer** (HTML/JS/CSS). Seules les **données** passent par l’API sur ton serveur.

**Coût : 0 €** (repo public = Mac GitHub gratuit)

---

## Secret GitHub

| Secret | Exemple |
|--------|---------|
| `BEER_SERVER_URL` | `https://ton-serveur.example/beer` |

Pas d’URL dans le code public — injectée au build dans `www/mobile-env.js`.

---

## Mettre à jour le front Beer

Sur le serveur Plexi (quand Beer change) :

```bash
cd /home/eiter/beer-mobile
BEER_SERVER_URL="https://ton-serveur/beer" npm run sync:www
git add www/
git commit -m "sync: front Beer"
git push
```

Puis **Actions** → **Run workflow**.

---

## Côté serveur Beer (une fois)

Le conteneur Beer doit avoir `BEER_MOBILE_CORS=1` (déjà dans docker-compose) pour que l’app iOS puisse se connecter.

```bash
cd /home/eiter/beer && docker compose up -d
```

---

## Installer l’IPA

1. **Artifacts** → `PlexiBeer.ipa`
2. **AltStore** → **+** → installe
3. Wi‑Fi maison ou VPN Plexi pour l’API
4. **Réglages iPhone** → Plexi Beer → autoriser **Caméra**

---

## Offline

- UI Beer **dans l’IPA** → ouvre sans charger le site
- Enregistrement bière **sans réseau** → file d’attente → sync auto
- Lookup EAN catalogue → **réseau requis**