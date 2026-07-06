#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

let remote = (process.env.BEER_SERVER_URL || "").trim().replace(/\/$/, "");
const lanHost = (process.env.PLEXI_HOST || "192.168.1.50").trim();
const lanPort = (process.env.PLEXI_NGINX_HUB_PORT || "8444").trim();

if (!remote) {
  console.error("BEER_SERVER_URL manquant");
  process.exit(1);
}

if (/:8443(\/|$)/.test(remote)) {
  console.warn("WARN: :8443 → :8444");
  remote = remote.replace(":8443", ":8444");
}

// LAN direct : le DNS freeboxos.fr pointe le WAN — l'iPhone en Wi‑Fi ne peut pas joindre :8444 via le FQDN
const lan = `https://${lanHost}:${lanPort}/beer/`;
const remoteBase = remote ? `${remote.replace(/\/$/, "")}/` : "";
const fallbacks = [...new Set([lan, remoteBase].filter(Boolean))];

const swift = `// Généré au build CI — NE PAS ÉDITER
import Foundation

enum BuildConfig {
    /// URL LAN directe (prioritaire — évite hairpin NAT Freebox)
    static let apiBaseString = ${JSON.stringify(lan)}
    static let apiFallbacks: [String] = ${JSON.stringify(fallbacks)}
    static var apiBase: URL { URL(string: apiBaseString)! }
}
`;

fs.writeFileSync(
  path.join(__dirname, "..", "native-ios", "Config", "Build.xcconfig"),
  `BEER_API_BASE = ${lan}\n`,
);
fs.writeFileSync(
  path.join(__dirname, "..", "native-ios", "BeerNative", "Sources", "BuildConfig.generated.swift"),
  swift,
);
console.log(`API LAN : ${lan}`);
console.log(`Fallbacks : ${fallbacks.join(", ")}`);