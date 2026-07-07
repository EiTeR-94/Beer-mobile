#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const base = (
  process.env.BEER_SERVER_URL || "https://eiter.freeboxos.fr/beer"
).trim().replace(/\/$/, "") + "/";

const swift = `// Généré au build CI — NE PAS ÉDITER
import Foundation

enum BuildConfig {
    static let apiBaseString = ${JSON.stringify(base)}
    static let apiFallbacks: [String] = []
    static var apiBase: URL { URL(string: apiBaseString)! }
}
`;

fs.writeFileSync(
  path.join(__dirname, "..", "native-ios", "Config", "Build.xcconfig"),
  `BEER_API_BASE = ${base}\n`,
);
fs.writeFileSync(
  path.join(__dirname, "..", "native-ios", "BeerNative", "Sources", "BuildConfig.generated.swift"),
  swift,
);
console.log(`API : ${base}`);