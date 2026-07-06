#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const base = (process.env.BEER_SERVER_URL || "").trim().replace(/\/$/, "");
if (!base) {
  console.error("BEER_SERVER_URL manquant");
  process.exit(1);
}

const out = path.join(__dirname, "..", "native-ios", "Config", "Build.xcconfig");
const body = `// Généré au build CI — ne pas committer l'URL réelle
BEER_API_BASE = ${base}
`;
fs.writeFileSync(out, body);
console.log("native-ios/Config/Build.xcconfig écrit");