# Trouve APPLE_TEAM_ID (compte gratuit AltStore) — Windows
# Usage : powershell -ExecutionPolicy Bypass -File scripts\extract-team-id.ps1

param(
  [string]$ProfilePath = "",
  [string]$IpaPath = ""
)

function Get-TeamFromBytes([byte[]]$bytes) {
  foreach ($enc in @(
      [Text.Encoding]::UTF8,
      [Text.Encoding]::GetEncoding(28591)
    )) {
    $text = $enc.GetString($bytes)
    if ($text -match "TeamIdentifier[\s\S]{0,120}?([A-Z0-9]{10})") { return $Matches[1] }
    if ($text -match "ApplicationIdentifierPrefix[\s\S]{0,120}?([A-Z0-9]{10})") { return $Matches[1] }
    if ($text -match "com\.apple\.developer\.team-identifier[\s\S]{0,120}?([A-Z0-9]{10})") { return $Matches[1] }
  }
  return $null
}

function Show-Team($team, $source) {
  Write-Host ""
  Write-Host "========== TON APPLE_TEAM_ID ==========" -ForegroundColor Green
  Write-Host $team
  Write-Host "Source : $source" -ForegroundColor DarkGray
  Write-Host "=======================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "GitHub → Beer-mobile → Settings → Secrets → APPLE_TEAM_ID"
}

function Read-TeamFromProvisionFile($path) {
  if (-not (Test-Path $path)) { return $null }
  return Get-TeamFromBytes ([IO.File]::ReadAllBytes($path))
}

function Read-TeamFromIpa($path) {
  if (-not (Test-Path $path)) { return $null }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like "*embedded.mobileprovision" } | Select-Object -First 1
    if (-not $entry) { return $null }
    $stream = $entry.Open()
    try {
      $ms = New-Object IO.MemoryStream
      $stream.CopyTo($ms)
      return Get-TeamFromBytes $ms.ToArray()
    } finally { $stream.Close() }
  } finally { $zip.Dispose() }
}

if ($ProfilePath -ne "") {
  $t = Read-TeamFromProvisionFile $ProfilePath
  if ($t) { Show-Team $t $ProfilePath; exit 0 }
  Write-Host "Fichier fourni mais Team ID introuvable : $ProfilePath" -ForegroundColor Red
  exit 1
}

if ($IpaPath -ne "") {
  $t = Read-TeamFromIpa $IpaPath
  if ($t) { Show-Team $t $IpaPath; exit 0 }
  Write-Host "IPA fourni mais Team ID introuvable : $IpaPath" -ForegroundColor Red
  exit 1
}

Write-Host "=== Methode 1 : chercher des .ipa (AltStore) ===" -ForegroundColor Cyan
$ipaRoots = @(
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Downloads",
  "$env:USERPROFILE\Documents",
  "C:\Users\BunnY\Desktop"
) | Select-Object -Unique

foreach ($root in $ipaRoots) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem -Path $root -Recurse -Filter "*.ipa" -ErrorAction SilentlyContinue | ForEach-Object {
    $t = Read-TeamFromIpa $_.FullName
    if ($t) { Show-Team $t $_.FullName; exit 0 }
  }
}

Write-Host "=== Methode 2 : chercher .mobileprovision ===" -ForegroundColor Cyan
$provRoots = @(
  "$env:LOCALAPPDATA\AltServer",
  "$env:APPDATA\AltServer",
  "$env:LOCALAPPDATA\AltStore",
  "$env:APPDATA\AltStore",
  "$env:USERPROFILE\.altstore",
  "$env:USERPROFILE\Apple\MobileDevice",
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Downloads"
) | Select-Object -Unique

foreach ($root in $provRoots) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem -Path $root -Recurse -Filter "*.mobileprovision" -ErrorAction SilentlyContinue | ForEach-Object {
    $t = Read-TeamFromProvisionFile $_.FullName
    if ($t) { Show-Team $t $_.FullName; exit 0 }
  }
}

Write-Host ""
Write-Host "RIEN TROUVE sur ce PC." -ForegroundColor Yellow
Write-Host ""
Write-Host "=== Methode 3 : 3uTools (la plus fiable) ===" -ForegroundColor Cyan
Write-Host "1. Telecharge 3uTools : https://www.3u.com"
Write-Host "2. Branche l'iPhone USB"
Write-Host "3. Onglet iDevice -> Provisioning Profiles (ou Profils)"
Write-Host "4. Note le Team ID (10 caracteres) a cote de ton Apple ID"
Write-Host ""
Write-Host "=== Methode 4 : fichier manuel ===" -ForegroundColor Cyan
Write-Host "Si tu as un .ipa ou .mobileprovision quelque part :"
Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\extract-team-id.ps1 -IpaPath "C:\chemin\app.ipa"'
Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\extract-team-id.ps1 -ProfilePath "C:\chemin\profil.mobileprovision"'
exit 1