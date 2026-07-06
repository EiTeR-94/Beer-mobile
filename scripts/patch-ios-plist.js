#!/usr/bin/env node
/**
 * Après `npx cap add ios` : ajuste Info.plist (WKWebView, navigation).
 * Relancer : npm run postinstall  ou  node scripts/patch-ios-plist.js
 */
const fs = require("fs");
const path = require("path");

const plistPath = path.join(
  __dirname,
  "..",
  "ios",
  "App",
  "App",
  "Info.plist",
);

if (!fs.existsSync(plistPath)) {
  process.exit(0);
}

let xml = fs.readFileSync(plistPath, "utf8");

if (!xml.includes("<key>ITSAppUsesNonExemptEncryption</key>")) {
  xml = xml.replace(
    "</dict>\n</plist>",
    "  <key>ITSAppUsesNonExemptEncryption</key>\n  <false/>\n</dict>\n</plist>",
  );
}

if (!xml.includes("<key>NSCameraUsageDescription</key>")) {
  xml = xml.replace(
    "</dict>\n</plist>",
    "  <key>NSCameraUsageDescription</key>\n  <string>Scanner les codes-barres des bouteilles.</string>\n</dict>\n</plist>",
  );
}

fs.writeFileSync(plistPath, xml);
console.log("Info.plist patché (export compliance + caméra future)");