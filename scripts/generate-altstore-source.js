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

const STABLE_VERSION = "3.3.0";

function versionReleaseNotes(ver, buildNum) {
  if (ver === STABLE_VERSION) {
    return ascii(
      "v3.3.0 Stable — version figee Plexi. UI polish, mode hors ligne, admin invite, scan + toasts, AltStore OK."
    );
  }
  if (ver === "3.3.1") {
    return ascii("bugs fix");
  }
  return ascii(`Build ${buildNum} — Beer Log native`);
}

const githubAssetBase = `https://github.com/EiTeR-94/Beer-mobile/releases/download/ios-build-${build}`;
const homelabBase = (
  process.env.MOBILE_DIST_BASE_URL || "https://eiter.freeboxos.fr:8444/mobile/beer"
).replace(/\/$/, "");
const assetBase = distMode === "homelab" ? homelabBase : githubAssetBase;

const appLongDescription = ascii(
  "Beer Log, c'est ton journal de bieres sur le serveur Plexi d'EiTeR — 100% natif iPhone, zero WebView. " +
    "Tu scannes un code-barres, tu cherches sur Untappd, tu poses la photo du verre, tu notes avec des demi-etoiles, " +
    "saveurs et houblons. Historique, galerie, liste a boire, idees cadeaux : tout est la, pense pour le quotidien entre amis. " +
    "Mode hors ligne : tes degustations restent sur l'iPhone et partent au serveur des que le Wi-Fi maison ou le VPN Plexi revient. " +
    "Connexion : eiter.freeboxos.fr. Admin : comptes, invitations privees, referentiels. " +
    "v3.3.1 — la version de reference du homelab. Fait avec soin pour Plexi, pas pour l'App Store."
);

const source = {
  name: ascii("Plexi Homelab"),
  subtitle: ascii("Apps perso EiTeR — homelab Freebox + Plexi"),
  description: ascii(
    "Source privee pour installer et mettre a jour les apps iOS du homelab Plexi (serveur .50, LAN/VPN). " +
      "Beer Log : carnet de degustation natif, sync sur ton serveur maison. MAJ auto apres build GitHub vert."
  ),
  website: "https://eiter.freeboxos.fr/beer/",
  tintColor: "#f59e0b",
  featuredApps: [bundleId],
  apps: [
    {
      name: ascii("Beer Log"),
      bundleIdentifier: bundleId,
      developerName: "eiter",
      subtitle: ascii("Ton carnet de bieres sur Plexi"),
      localizedDescription: appLongDescription,
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
          localizedDescription: versionReleaseNotes(version, build),
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