#!/usr/bin/env node
/**
 * Valide altstore.json (ASCII strict + champs requis) — evite AltStore erreur 3840.
 * Usage: node scripts/validate-altstore-json.js [chemin/altstore.json] [taille-ipa-optionnelle]
 */
const fs = require("fs");
const path = require("path");

const file = process.argv[2] || path.join(__dirname, "..", "dist", "altstore.json");
const expectedIpaSize = process.argv[3] ? Number(process.argv[3]) : null;

if (!fs.existsSync(file)) {
  console.error(`Fichier introuvable: ${file}`);
  process.exit(1);
}

const raw = fs.readFileSync(file);
const text = raw.toString("utf8");

if (raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf) {
  console.error("ERREUR: BOM UTF-8 interdit");
  process.exit(1);
}

if (/[^\x00-\x7F]/.test(text)) {
  const bad = [...text].find((ch) => ch.charCodeAt(0) > 127);
  console.error(`ERREUR: caractere non-ASCII (${bad}) — AltStore 3840`);
  process.exit(1);
}

let data;
try {
  data = JSON.parse(text);
} catch (err) {
  console.error(`ERREUR: JSON invalide — ${err.message}`);
  process.exit(1);
}

const app = data.apps && data.apps[0];
const ver = app && app.versions && app.versions[0];
if (!app || !ver) {
  console.error("ERREUR: structure apps[0].versions[0] manquante");
  process.exit(1);
}

const BAD_URL_PATTERNS = [
  "/releases/latest/download/",
  "/releases/download/",
  "raw.githubusercontent.com",
];

const BAD_URL_PATTERNS_STRICT = [...BAD_URL_PATTERNS, ":8444", "192.168."];

function collectUrls(value, out = []) {
  if (typeof value === "string" && /^https?:\/\//.test(value)) out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => collectUrls(v, out));
  else if (value && typeof value === "object")
    Object.values(value).forEach((v) => collectUrls(v, out));
  return out;
}

const urls = collectUrls(data);
for (const url of urls) {
  const patterns =
    url === String(ver.downloadURL || "") || url === String(app.iconURL || "")
      ? BAD_URL_PATTERNS
      : BAD_URL_PATTERNS_STRICT;
  for (const bad of patterns) {
    if (url.includes(bad)) {
      console.error(`ERREUR: URL interdite (${bad}) — ${url}`);
      process.exit(1);
    }
  }
}

const url = String(ver.downloadURL || "");
if (!url.endsWith("/PlexiBeer.ipa")) {
  console.error(`ERREUR: downloadURL inattendu — ${url}`);
  process.exit(1);
}

const icon = String(app.iconURL || "");
if (!icon.endsWith("/icon-180.png")) {
  console.error(`ERREUR: iconURL inattendu — ${icon}`);
  process.exit(1);
}

const size = Number(ver.size);
if (!Number.isFinite(size) || size < 100000) {
  console.error(`ERREUR: size invalide — ${ver.size}`);
  process.exit(1);
}

if (expectedIpaSize != null && size !== expectedIpaSize) {
  console.error(`ERREUR: size manifest ${size} != IPA ${expectedIpaSize}`);
  process.exit(1);
}

console.log(
  `OK altstore.json — v${ver.version} build ${ver.buildVersion} size=${size}`
);