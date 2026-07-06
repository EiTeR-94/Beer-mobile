#!/usr/bin/env node
/**
 * Injecte APPLE_TEAM_ID dans le projet Xcode (obligatoire sur GitHub Actions).
 * Relancer après : npx cap sync ios
 */
const fs = require("fs");
const path = require("path");

const teamId = (process.env.APPLE_TEAM_ID || "").trim();
if (!teamId) {
  console.error("APPLE_TEAM_ID manquant (secret GitHub obligatoire)");
  process.exit(1);
}

const pbx = path.join(
  __dirname,
  "..",
  "ios",
  "App",
  "App.xcodeproj",
  "project.pbxproj",
);

if (!fs.existsSync(pbx)) {
  console.error("project.pbxproj introuvable — lance d'abord npx cap add ios");
  process.exit(1);
}

let content = fs.readFileSync(pbx, "utf8");

if (/DEVELOPMENT_TEAM = /.test(content)) {
  content = content.replace(
    /DEVELOPMENT_TEAM = [^;]+;/g,
    `DEVELOPMENT_TEAM = ${teamId};`,
  );
} else {
  content = content.replace(
    /(buildSettings = \{)/g,
    `$1\n\t\t\t\tDEVELOPMENT_TEAM = ${teamId};`,
  );
}

fs.writeFileSync(pbx, content);
console.log(`DEVELOPMENT_TEAM = ${teamId} appliqué dans project.pbxproj`);