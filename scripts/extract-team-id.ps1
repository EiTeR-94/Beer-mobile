# Trouve ton Team ID Apple (compte gratuit AltStore) — Windows PowerShell
# Usage : powershell -File scripts/extract-team-id.ps1

function Get-TeamFromMobileProvision($path) {
  $raw = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.Encoding]::UTF8.GetString($raw)
  if ($text -match "TeamIdentifier.*?<array>\s*<string>([A-Z0-9]{10})</string>") {
    return $Matches[1]
  }
  if ($text -match "<key>ApplicationIdentifierPrefix</key>\s*<array>\s*<string>([A-Z0-9]{10})</string>") {
    return $Matches[1]
  }
  return $null
}

$roots = @(
  "$env:LOCALAPPDATA\AltServer",
  "$env:APPDATA\AltServer",
  "$env:USERPROFILE\.altstore",
  "$env:LOCALAPPDATA\AltStore"
)

Write-Host "Recherche de profils AltStore / .mobileprovision ..." -ForegroundColor Cyan

$files = @()
foreach ($root in $roots) {
  if (Test-Path $root) {
    $files += Get-ChildItem -Path $root -Recurse -Filter "*.mobileprovision" -ErrorAction SilentlyContinue
  }
}

if ($files.Count -eq 0) {
  Write-Host ""
  Write-Host "Aucun profil trouvé automatiquement." -ForegroundColor Yellow
  Write-Host "Branche l'iPhone, ouvre AltStore, rafraîchis une app, puis relance ce script."
  Write-Host ""
  Write-Host "Ou exporte un .mobileprovision depuis 3uTools / iMazing et lance :"
  Write-Host '  powershell -File scripts/extract-team-id.ps1 -ProfilePath "C:\chemin\profil.mobileprovision"'
  exit 1
}

$teams = @{}
foreach ($f in $files) {
  $tid = Get-TeamFromMobileProvision $f.FullName
  if ($tid) { $teams[$tid] = $f.FullName }
}

if ($teams.Count -eq 0) {
  Write-Host "Profils trouvés mais Team ID illisible." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "========== TON APPLE_TEAM_ID ==========" -ForegroundColor Green
foreach ($kv in $teams.GetEnumerator()) {
  Write-Host $kv.Key
  Write-Host "(fichier : $($kv.Value))" -ForegroundColor DarkGray
}
Write-Host "=======================================" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub → Beer-mobile → Settings → Secrets → New secret"
Write-Host "Nom : APPLE_TEAM_ID"
Write-Host "Valeur : le code 10 caractères ci-dessus"