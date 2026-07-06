#!/usr/bin/env node
/** Injecte BEER_SERVER_URL (secret GitHub) avant le build — pas d'URL perso dans le repo */
const fs = require("fs");
const path = require("path");

const url = (process.env.BEER_SERVER_URL || "").trim();
if (!url) {
  console.error(
    "BEER_SERVER_URL manquant — ajoute le secret GitHub (ex. https://ton-serveur/beer/)",
  );
  process.exit(1);
}

const configPath = path.join(__dirname, "..", "capacitor.config.json");
const cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));

const normalized = url.endsWith("/") ? url : `${url}/`;
cfg.server = cfg.server || {};
cfg.server.url = normalized;

try {
  const host = new URL(normalized).hostname;
  const extra = (process.env.BEER_ALLOW_NAVIGATION || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  cfg.server.allowNavigation = [host, ...extra];
} catch {
  console.warn("URL invalide pour allowNavigation");
}

fs.writeFileSync(configPath, `${JSON.stringify(cfg, null, 2)}\n`);
console.log("capacitor.config.json : URL injectée depuis secret");