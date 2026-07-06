#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const base = (process.env.BEER_SERVER_URL || "").trim().replace(/\/$/, "");
if (!base) {
  console.error("BEER_SERVER_URL manquant");
  process.exit(1);
}

let version = "mobile";
try {
  version = fs
    .readFileSync(path.join(__dirname, "..", "..", "beer", "VERSION"), "utf8")
    .trim();
} catch {
  /* www déjà synchronisé */
}

const js = `// API Beer — injecté au build CI
window.BEER_MOBILE = true;
window.BEER_ROOT = ${JSON.stringify(base)};
window.BEER_VERSION = ${JSON.stringify(version)};
`;

fs.writeFileSync(path.join(__dirname, "..", "www", "mobile-env.js"), js);
console.log("mobile-env.js écrit");