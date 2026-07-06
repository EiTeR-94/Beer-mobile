#!/usr/bin/env node
/** Rappel : définir l’icône dans Xcode (Assets.xcassets) depuis assets/icon.png */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const icon = path.join(root, "assets", "icon.png");
if (!fs.existsSync(icon)) {
  console.warn("assets/icon.png manquant");
  process.exit(0);
}
console.log("Icône source : assets/icon.png (1024 recommandé — utilise icon-512 actuel)");
console.log("Sur MacinCloud : Xcode → App → Assets → AppIcon → glisser icon.png");