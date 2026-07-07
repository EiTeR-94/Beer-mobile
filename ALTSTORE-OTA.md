# Beer Log sur iPhone — mode d’emploi simple

## Ajouter la source (1 fois)

Sur l’iPhone, dans **AltStore** :

1. Onglet **Sources** (ou Réglages → Sources)
2. Bouton **+**
3. Colle **exactement** :

```
https://github.com/EiTeR-94/Beer-mobile/releases/latest/download/altstore.json
```

4. Valide. Tu dois voir la source **Plexi Homelab** avec **Beer Log** (v3.3.0 Stable).

> **N’utilise pas** `192.168.1.50` — le certificat SSL ne correspond pas → AltStore affiche « inconnu / pas sécurisé ».

## Installer ou mettre à jour

1. Wi‑Fi maison + **AltServer** allumé sur ton PC (comme d’habitude)
2. AltStore → source **Plexi Homelab** → **Beer Log**
3. **Installer** ou **Mettre à jour** (1 bouton)

Chaque push sur `main` déclenche un build GitHub (~10 min). Ensuite AltStore propose la MAJ toute seule (parfois après avoir ouvert AltStore une fois).

## Ça ne marche pas ?

| Message AltStore | Cause | Fix |
|------------------|-------|-----|
| Inconnu / pas sécurisé | Mauvaise URL ou fichier absent | URL GitHub ci-dessus, pas l’IP |
| Impossible de télécharger | Pas de release encore | Attendre build vert sur GitHub Actions |
| Erreur 2005 / NSCocoaErrorDomain 3840 | JSON invalide (souvent page HTML 403/404) | Source **GitHub** ci-dessus ; Wi‑Fi ou VPN si URL `:8444` ; supprimer/ré-ajouter la source |
| Erreur 2005 à l’install | AltServer / iTunes | Voir GUIDE-GITHUB.md |

## Option LAN (plus tard, optionnel)

Miroir sur le serveur `.50` pour télécharger l’IPA en local — pas nécessaire si GitHub fonctionne.