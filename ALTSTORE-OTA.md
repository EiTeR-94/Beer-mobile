# Beer Log iOS — MAJ automatiques (AltStore)

Compte Apple **gratuit** = pas d’App Store ni TestFlight. Le plus proche d’une « vraie » MAJ auto :

1. **GitHub Actions** build à chaque push sur `main`
2. **Serveur .50** récupère l’IPA (~15 min)
3. **AltStore** sur l’iPhone propose **Mettre à jour** (1 tap si AltServer est sur le Wi‑Fi)

## Configuration unique (iPhone)

1. AltStore → **Sources** → **+**
2. URL : `https://192.168.1.50:8444/mobile/beer/altstore.json`
3. Installer **Beer Log** depuis cette source (une fois)

Ensuite : quand une nouvelle build est publiée sur le serveur, AltStore affiche la MAJ (badge / onglet News). **Mettre à jour** → AltServer re-signe et installe.

## Configuration serveur (.50)

### 1. Token GitHub (lecture Actions)

Créer un fine-grained token (repo `Beer-mobile`) : **Actions: Read**, **Contents: Read**.

```bash
sudo install -d -m 750 -o root -g eiter /etc/plexi
echo 'ghp_…' | sudo tee /etc/plexi/beer-mobile-github.token >/dev/null
sudo chmod 640 /etc/plexi/beer-mobile-github.token
sudo chown root:eiter /etc/plexi/beer-mobile-github.token
```

### 2. Nginx + répertoire web

```bash
sudo mkdir -p /var/www/beer-mobile
sudo chown www-data:www-data /var/www/beer-mobile
/home/eiter/scripts/deploy-plexi-network.sh
sudo nginx -t && sudo systemctl reload nginx
```

### 3. Timer sync (toutes les 15 min)

```bash
sudo cp /home/eiter/scripts/systemd/beer-mobile-sync.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now beer-mobile-sync.timer
```

Sync manuelle :

```bash
/home/eiter/scripts/beer-mobile-sync-github.sh
```

## Limites (honnêtes)

| App Store / TestFlight | AltStore homelab |
|------------------------|------------------|
| MAJ silencieuses push | Notification + 1 tap « Mettre à jour » |
| Pas de limite 7 jours | Re-signature AltServer tous les 7 j (background refresh) |
| Partout | LAN/VPN uniquement (sécurité) |

Pour du **100 % App Store** : compte Apple Developer 99 €/an + TestFlight.