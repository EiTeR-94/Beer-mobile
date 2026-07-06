#!/usr/bin/env ruby
# OBSOLÈTE pour compte gratuit (AltStore) — le portail web Apple refuse l'accès.
# Utilise GitHub Actions → Build iOS IPA (sans FASTLANE_SESSION).

abort <<~MSG

  ══════════════════════════════════════════════════════════════════════
  PAS BESOIN DE CE SCRIPT (compte gratuit AltStore)
  ══════════════════════════════════════════════════════════════════════

  Ce script se connecte au PORTAIL developer.apple.com.
  Avec un compte gratuit tu as souvent :
    « Access Unavailable — only for developers enrolled in a program »

  Apple répond alors :
    Invalid username and password / Unauthorized Access

  Ce n'est PAS ton mot de passe qui est faux. Le portail web te bloque.

  ── À faire à la place ──

  1. GitHub → repo Beer-mobile → Settings → Secrets :
       APPLE_ID
       APPLE_APP_SPECIFIC_PASSWORD   (mot de passe POUR APP sur appleid.apple.com)
       IOS_DEVICE_UDID

  2. Supprime le secret FASTLANE_SESSION (inutile).

  3. Actions → « Build iOS IPA » → Run workflow

  Plan B immédiat : Safari → https://eiter.freeboxos.fr:8443/beer/
                    → Partager → Sur l'écran d'accueil

  ══════════════════════════════════════════════════════════════════════

MSG