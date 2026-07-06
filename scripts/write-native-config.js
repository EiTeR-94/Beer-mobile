#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

let base = (process.env.BEER_SERVER_URL || "").trim().replace(/\/$/, "");
if (!base) {
  console.error("BEER_SERVER_URL manquant");
  process.exit(1);
}

// 8443 = sslh + PROXY protocol → incompatible apps natives (URLSession)
if (/:8443(\/|$)/.test(base)) {
  console.warn("WARN: :8443 utilise PROXY protocol — bascule automatique vers :8444");
  base = base.replace(":8443", ":8444");
}

const swift = `// Généré au build CI — NE PAS ÉDITER
import Foundation

enum BuildConfig {
    static let apiBaseString = ${JSON.stringify(base)}
    static var apiBase: URL {
        URL(string: apiBaseString)!
    }
}
`;

const xcconfig = `// Généré au build CI
BEER_API_BASE = ${base}
`;

fs.writeFileSync(
  path.join(__dirname, "..", "native-ios", "Config", "Build.xcconfig"),
  xcconfig,
);
fs.writeFileSync(
  path.join(__dirname, "..", "native-ios", "BeerNative", "Sources", "BuildConfig.generated.swift"),
  swift,
);
console.log(`Config API : ${base}`);