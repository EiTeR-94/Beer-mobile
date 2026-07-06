#!/usr/bin/env node
/**
 * Copie le front Beer dans www/ pour l'app Capacitor embarquée.
 * Source : ../beer/app/static (serveur Plexi) ou BEER_STATIC_DIR
 */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const beerStatic =
  process.env.BEER_STATIC_DIR ||
  path.join(root, "..", "beer", "app", "static");
const beerVersionFile = path.join(root, "..", "beer", "VERSION");
const www = path.join(root, "www");

function readVersion() {
  try {
    return fs.readFileSync(beerVersionFile, "utf8").trim();
  } catch {
    return "mobile";
  }
}

function rmrf(dir) {
  if (!fs.existsSync(dir)) return;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) rmrf(p);
    else fs.unlinkSync(p);
  }
  fs.rmdirSync(dir);
}

function mkdirp(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function copyFile(src, dest) {
  mkdirp(path.dirname(dest));
  fs.copyFileSync(src, dest);
}

function copyDir(src, dest) {
  mkdirp(dest);
  for (const ent of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, ent.name);
    const d = path.join(dest, ent.name);
    if (ent.isDirectory()) copyDir(s, d);
    else copyFile(s, d);
  }
}

function patchHtml(html, version) {
  return html
    .replace(/\{\{ROOT_PATH\}\}\/static\//g, "./static/")
    .replace(/\{\{ROOT_PATH\}\}/g, "")
    .replace(/\{\{VERSION\}\}/g, version)
    .replace(/<link rel="stylesheet" href="\/plexi-assets[^"]*"[^>]*>\s*/g, "")
    .replace(/<script[\s\S]*?hub-nav\.js[\s\S]*?<\/script>\s*/g, "");
}

function patchAppJs(code) {
  let out = code.replace(
    /return fetch\(api\(path\), \{ credentials: "same-origin", \.\.\.options \}\);/,
    'const creds = window.BEER_MOBILE ? "include" : "same-origin";\n    return fetch(api(path), { credentials: creds, ...options });',
  );
  out = out.replace(
    /credentials: "same-origin"/g,
    'credentials: (window.BEER_MOBILE ? "include" : "same-origin")',
  );

  if (!out.includes("function isCapacitorApp()")) {
    out = out.replace(
      /function detectScanProfile\(\) \{/,
      `function isCapacitorApp() {
    return !!(window.BEER_MOBILE || (window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()));
  }

  function detectScanProfile() {`,
    );
    out = out.replace(
      /if \(isIOS && isPwa\) \{/,
      `if (isIOS && isCapacitorApp()) {
      return { mode: "live", reason: "ios-capacitor", autoScan: true, liveFailed: false };
    }
    if (isIOS && isPwa) {`,
    );
  }

  out = out.replace(
    /window\.location\.replace\(api\("\/"\)\);/g,
    'window.location.replace(window.BEER_MOBILE ? "./login.html" : api("/"));',
  );

  out = out.replace(
    /function logout\(\) \{[\s\S]*?window\.location\.replace\(api\("\/logout"\)\);[\s\S]*?\}/,
    `function logout() {
    if (window.BEER_MOBILE) {
      fetch(api("/api/logout"), { method: "POST", credentials: "include" })
        .catch(function () {})
        .finally(function () {
          clearBeerSession();
          window.location.replace("./login.html");
        });
      return;
    }
    window.location.replace(api("/logout"));
  }`,
  );

  out = out.replace(
    /registerServiceWorker\(\);/,
    "if (!window.BEER_MOBILE) registerServiceWorker();",
  );

  return out;
}

function patchLoginJs(code) {
  return code
    .replace(
      /window\.location\.replace\(api\("\/app"\)\);/g,
      'window.location.replace(window.BEER_MOBILE ? "./index.html" : api("/app"));',
    )
    .replace(
      /if \(d\?\.user\) window\.location\.replace\(api\("\/app"\)\);/,
      'if (d?.user) window.location.replace(window.BEER_MOBILE ? "./index.html" : api("/app"));',
    )
    .replace(
      /if \("serviceWorker" in navigator\) \{[\s\S]*?\}\s*\n\s*fetch/,
      "fetch",
    );
}

function writeMobileEnv(apiBase) {
  const base = (apiBase || process.env.BEER_SERVER_URL || "").trim().replace(/\/$/, "");
  const js = `// Généré au build — API Beer distante, UI locale dans l'IPA
window.BEER_MOBILE = true;
window.BEER_ROOT = ${JSON.stringify(base)};
window.BEER_VERSION = ${JSON.stringify(readVersion())};
`;
  fs.writeFileSync(path.join(www, "mobile-env.js"), js);
}

function stripInlineBeerRoot(html) {
  return html.replace(/<script>\s*window\.BEER_ROOT[\s\S]*?<\/script>\s*/g, "");
}

function injectMobileEnv(html) {
  html = stripInlineBeerRoot(html);
  if (html.includes("mobile-env.js")) return html;
  return html.replace(
    /<script src="(?:\.\/)?static\//,
    '<script src="./mobile-env.js"></script>\n  <script src="./static/',
  );
}

if (!fs.existsSync(beerStatic)) {
  console.error(`Source Beer introuvable : ${beerStatic}`);
  console.error("Définis BEER_STATIC_DIR ou lance depuis le serveur Plexi.");
  process.exit(1);
}

const version = readVersion();
const staticWww = path.join(www, "static");
rmrf(staticWww);
mkdirp(staticWww);

for (const name of ["style.css", "app.js", "login.js", "ptr.js"]) {
  let content = fs.readFileSync(path.join(beerStatic, name), "utf8");
  if (name === "app.js") content = patchAppJs(content);
  if (name === "login.js") content = patchLoginJs(content);
  fs.writeFileSync(path.join(staticWww, name), content);
}

copyDir(path.join(beerStatic, "icons"), path.join(staticWww, "icons"));

for (const page of ["index.html", "login.html"]) {
  let html = fs.readFileSync(path.join(beerStatic, page), "utf8");
  html = patchHtml(html, version);
  html = injectMobileEnv(html);
  const outName = page === "index.html" ? "index.html" : "login.html";
  fs.writeFileSync(path.join(www, outName), html);
}

writeMobileEnv(process.env.BEER_SERVER_URL || "");

console.log(`www/ synchronisé depuis Beer v${version}`);
console.log(`  → ${www}`);