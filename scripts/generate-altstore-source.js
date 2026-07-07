#!/usr/bin/env node
/**
 * Genere altstore.json pour MAJ OTA AltStore (ASCII strict — evite erreur 3840).
 * Usage: node scripts/generate-altstore-source.js [chemin/ipa] [buildVersion]
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const projectYml = path.join(ROOT, "native-ios", "project.yml");
const ipaPath = process.argv[2] || path.join(ROOT, "build", "PlexiBeer.ipa");
const buildOverride = process.argv[3];

const distMode = process.env.MOBILE_DIST_MODE || "github"; // github | homelab

function ymlVal(key, fallback = "") {
  const raw = fs.readFileSync(projectYml, "utf8");
  const m = raw.match(new RegExp(`^\\s*${key}:\\s*"?([^"\\n#]+)"?`, "m"));
  return m ? m[1].trim() : fallback;
}

/** AltStore / NSCocoa 3840 : JSON 100 % ASCII (pas d'accents). */
function ascii(s) {
  return String(s)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\x20-\x7E]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
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

const githubAssetBase = `https://github.com/EiTeR-94/Beer-mobile/releases/download/ios-build-${build}`;
const homelabBase = (
  process.env.MOBILE_DIST_BASE_URL || "https://eiter.freeboxos.fr:8444/mobile/beer"
).replace(/\/$/, "");
const assetBase = distMode === "homelab" ? homelabBase : githubAssetBase;

const source = {
  name: ascii("Plexi Homelab"),
  subtitle: ascii("Beer Log iOS - MAJ auto LAN/VPN"),
  description: ascii(
    "Source privee Plexi. Ajoute cette URL une fois dans AltStore > Sources. MAJ apres build GitHub vert."
  ),
  website: "https://eiter.freeboxos.fr/beer/",
  tintColor: "#f59e0b",
  featuredApps: [bundleId],
  apps: [
    {
      name: ascii("Beer Log"),
      bundleIdentifier: bundleId,
      developerName: "eiter",
      subtitle: ascii("Journal de degustation prive"),
      localizedDescription: ascii(
        "Beer Log iOS - scan, Untappd, photo, note, historique. Wi-Fi ou VPN Plexi."
      ),
      iconURL:
        distMode === "homelab"
          ? `${homelabBase}/icon-180.png`
          : "https://raw.githubusercontent.com/EiTeR-94/Beer-mobile/main/altstore/icon-180.png",
      tintColor: "#f59e0b",
      category: "lifestyle",
      appPermissions: {
        entitlements: [],
        privacy: {
          NSCameraUsageDescription: ascii(
            "Scanner les codes-barres et prendre des photos de tes degustations."
          ),
          NSLocalNetworkUsageDescription: ascii(
            "Connexion au serveur Beer Log sur ton reseau local Plexi (192.168.1.50)."
          ),
          NSPhotoLibraryUsageDescription: ascii(
            "Joindre une photo a ta degustation Beer Log."
          ),
        },
      },
      versions: [
        {
          version,
          buildVersion: String(build),
          date: today,
          localizedDescription: ascii(`Build ${build} - Beer Log native`),
          downloadURL: `${assetBase}/${ipaName}`,
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
const json = JSON.stringify(source, null, 2);
if (/[^\x00-\x7F]/.test(json)) {
  console.error("ERREUR: altstore.json contient des caracteres non-ASCII");
  process.exit(1);
}
fs.writeFileSync(outFile, json);
console.log(`OK ${outFile} — v${version} (build ${build}) size=${size}`);
console.log(`IPA URL: ${assetBase}/${ipaName}`);
if (distMode === "homelab") {
  console.log(`Source iPhone (LAN/VPN): ${homelabBase}/altstore.json`);
} else {
  console.log(
    "Source iPhone (GitHub): https://github.com/EiTeR-94/Beer-mobile/releases/latest/download/altstore.json"
  );
}