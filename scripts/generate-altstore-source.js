#!/usr/bin/env node
/**
 * Génère altstore.json pour MAJ OTA via source AltStore (homelab).
 * Usage: node scripts/generate-altstore-source.js [chemin/ipa] [buildVersion]
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const projectYml = path.join(ROOT, "native-ios", "project.yml");
const ipaPath = process.argv[2] || path.join(ROOT, "build", "PlexiBeer.ipa");
const buildOverride = process.argv[3];

const baseURL = (process.env.MOBILE_DIST_BASE_URL || "https://192.168.1.50:8444/mobile/beer")
  .replace(/\/$/, "");

function ymlVal(key, fallback = "") {
  const raw = fs.readFileSync(projectYml, "utf8");
  const m = raw.match(new RegExp(`^\\s*${key}:\\s*"?([^"\\n#]+)"?`, "m"));
  return m ? m[1].trim() : fallback;
}

const version = ymlVal("MARKETING_VERSION", "2.0.0");
const build = buildOverride || ymlVal("CURRENT_PROJECT_VERSION", "1");
const bundleId = ymlVal("PRODUCT_BUNDLE_IDENTIFIER", "fr.eiter.plexibeer");

if (!fs.existsSync(ipaPath)) {
  console.error(`IPA introuvable: ${ipaPath}`);
  process.exit(1);
}

const size = fs.statSync(ipaPath).size;
const ipaName = path.basename(ipaPath);
const today = new Date().toISOString().slice(0, 10);

const source = {
  name: "Plexi Homelab",
  subtitle: "Beer Log iOS — MAJ auto LAN/VPN",
  description:
    "Source privée Plexi. Ajoute cette URL une seule fois dans AltStore → Sources. " +
    "Les nouvelles versions apparaissent après sync GitHub → serveur (.50).",
  website: "https://192.168.1.50:8444/beer/",
  tintColor: "#f59e0b",
  featuredApps: [bundleId],
  apps: [
    {
      name: "Beer Log",
      bundleIdentifier: bundleId,
      developerName: "eiter",
      subtitle: "Journal de dégustation privé",
      localizedDescription:
        "App native Beer Log : scan EAN, Untappd, photo, note, historique. Wi‑Fi maison ou VPN Plexi.",
      iconURL: `${baseURL}/icon-180.png`,
      tintColor: "#f59e0b",
      category: "lifestyle",
      appPermissions: {
        entitlements: [],
        privacy: {
          NSCameraUsageDescription: "Scanner les codes-barres EAN des bouteilles de bière.",
          NSLocalNetworkUsageDescription:
            "Connexion au serveur Beer Log sur ton réseau local Plexi (192.168.1.50).",
          NSPhotoLibraryUsageDescription: "Joindre une photo à ta dégustation Beer Log.",
        },
      },
      versions: [
        {
          version,
          buildVersion: build,
          date: today,
          localizedDescription: `Build ${build} — sync automatique homelab`,
          downloadURL: `${baseURL}/${ipaName}`,
          size,
          minOSVersion: "16.0",
        },
      ],
    },
  ],
  news: [],
};

const outDir = process.env.ALTSTORE_OUT_DIR || path.join(ROOT, "dist");
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, "altstore.json");
fs.writeFileSync(outFile, JSON.stringify(source, null, 2));
console.log(`OK ${outFile} — v${version} (${build}) ${size} bytes`);
console.log(`Source URL iPhone: ${baseURL}/altstore.json`);