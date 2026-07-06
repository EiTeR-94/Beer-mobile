# APPLE_TEAM_ID sans rien installer — AltStore a deja cree un certificat Windows
# Usage : powershell -ExecutionPolicy Bypass -File scripts\extract-team-id.ps1

param(
  [string]$ProfilePath = "",
  [string]$IpaPath = ""
)

function Show-Team($team, $source) {
  Write-Host ""
  Write-Host "========== TON APPLE_TEAM_ID ==========" -ForegroundColor Green
  Write-Host $team
  Write-Host "Source : $source" -ForegroundColor DarkGray
  Write-Host "=======================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "GitHub -> Beer-mobile -> Settings -> Secrets -> APPLE_TEAM_ID"
  exit 0
}

function Team-From-Subject($subject) {
  if ($subject -match "Apple (Development|Distribution):.*\(([A-Z0-9]{10})\)") {
    return $Matches[2]
  }
  if ($subject -match "\(([A-Z0-9]{10})\)") {
    return $Matches[1]
  }
  return $null
}

function Get-TeamFromBytes([byte[]]$bytes) {
  foreach ($enc in @([Text.Encoding]::UTF8, [Text.Encoding]::GetEncoding(28591))) {
    $text = $enc.GetString($bytes)
    if ($text -match "TeamIdentifier[\s\S]{0,120}?([A-Z0-9]{10})") { return $Matches[1] }
    if ($text -match "ApplicationIdentifierPrefix[\s\S]{0,120}?([A-Z0-9]{10})") { return $Matches[1] }
  }
  return $null
}

if ($ProfilePath -ne "" -and (Test-Path $ProfilePath)) {
  $t = Get-TeamFromBytes ([IO.File]::ReadAllBytes($ProfilePath))
  if ($t) { Show-Team $t $ProfilePath }
}

if ($IpaPath -ne "" -and (Test-Path $IpaPath)) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($IpaPath)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like "*embedded.mobileprovision" } | Select-Object -First 1
    if ($entry) {
      $ms = New-Object IO.MemoryStream
      $entry.Open().CopyTo($ms)
      $t = Get-TeamFromBytes $ms.ToArray()
      if ($t) { Show-Team $t $IpaPath }
    }
  } finally { $zip.Dispose() }
}

Write-Host "=== Methode 1 : certificat AltStore (deja sur ton PC) ===" -ForegroundColor Cyan
$stores = @(
  "Cert:\CurrentUser\My",
  "Cert:\CurrentUser\CA",
  "Cert:\LocalMachine\My"
)
foreach ($store in $stores) {
  Get-ChildItem $store -ErrorAction SilentlyContinue | ForEach-Object {
    $subj = $_.Subject
    if ($subj -notmatch "Apple") { return }
    $t = Team-From-Subject $subj
    if ($t) { Show-Team $t "Certificat Windows : $subj" }
  }
}

Write-Host "=== Methode 2 : fichiers AltServer / iTunes ===" -ForegroundColor Cyan
$roots = @(
  "$env:LOCALAPPDATA\AltServer",
  "$env:APPDATA\AltServer",
  "$env:LOCALAPPDATA\Programs\AltServer",
  "$env:ProgramFiles\AltServer",
  "${env:ProgramFiles(x86)}\AltServer",
  "$env:APPDATA\Apple Computer\MobileSync\Backup"
)
foreach ($root in $roots) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem $root -Recurse -Include "*.mobileprovision","*.ipa" -ErrorAction SilentlyContinue | Select-Object -First 50 | ForEach-Object {
    if ($_.Extension -eq ".ipa") {
      Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
      try {
        $zip = [IO.Compression.ZipFile]::OpenRead($_.FullName)
        $entry = $zip.Entries | Where-Object { $_.FullName -like "*embedded.mobileprovision" } | Select-Object -First 1
        if ($entry) {
          $ms = New-Object IO.MemoryStream
          $entry.Open().CopyTo($ms)
          $t = Get-TeamFromBytes $ms.ToArray()
          if ($t) { $zip.Dispose(); Show-Team $t $_.FullName }
        }
        $zip.Dispose()
      } catch {}
    } else {
      $t = Get-TeamFromBytes ([IO.File]::ReadAllBytes($_.FullName))
      if ($t) { Show-Team $t $_.FullName }
    }
  }
}

Write-Host ""
Write-Host "Rien trouve." -ForegroundColor Red
Write-Host ""
Write-Host "Verifie qu'AltServer tourne et qu'AltStore est installe sur l'iPhone."
Write-Host "Puis relance ce script."
Write-Host ""
Write-Host "Commande directe (copie-colle) :"
Write-Host 'Get-ChildItem Cert:\CurrentUser\My | ? { $_.Subject -match "Apple" } | % { $_.Subject }'
exit 1