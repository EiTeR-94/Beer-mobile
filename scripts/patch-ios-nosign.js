#!/usr/bin/env node
/** Désactive la signature — AltStore re-signera sur ton PC Windows */
const fs = require("fs");
const path = require("path");

const pbx = path.join(
  __dirname,
  "..",
  "ios",
  "App",
  "App.xcodeproj",
  "project.pbxproj",
);

if (!fs.existsSync(pbx)) {
  console.log("project.pbxproj absent, skip");
  process.exit(0);
}

let content = fs.readFileSync(pbx, "utf8");

const flags = {
  CODE_SIGN_STYLE: "Manual",
  CODE_SIGN_IDENTITY: '""',
  CODE_SIGNING_ALLOWED: "NO",
  CODE_SIGNING_REQUIRED: "NO",
  DEVELOPMENT_TEAM: '""',
};

for (const [key, value] of Object.entries(flags)) {
  const re = new RegExp(`${key} = [^;]+;`, "g");
  if (re.test(content)) {
    content = content.replace(re, `${key} = ${value};`);
  } else {
    content = content.replace(
      /(buildSettings = \{)/g,
      `$1\n\t\t\t\t${key} = ${value};`,
    );
  }
}

fs.writeFileSync(pbx, content);
console.log("Signature iOS désactivée (IPA non signée → AltStore re-signera)");