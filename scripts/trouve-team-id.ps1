# Cherche APPLE_TEAM_ID partout — zero installation
# Sauvegarde le resultat sur le Bureau : team-id-resultat.txt

$out = "$env:USERPROFILE\Desktop\team-id-resultat.txt"
$lines = New-Object System.Collections.Generic.List[string]

function Add($s) { $lines.Add($s); Write-Host $s }

Add "=== Recherche APPLE_TEAM_ID $(Get-Date) ==="
Add ""

# 1. Tous les certificats (pas seulement Apple)
Add "--- CERTIFICATS Windows ---"
$found = $false
foreach ($store in @("Cert:\CurrentUser\My","Cert:\CurrentUser\Root","Cert:\LocalMachine\My")) {
  Get-ChildItem $store -ErrorAction SilentlyContinue | ForEach-Object {
    $subj = $_.Subject
    Add "  [$store] $subj"
    if ($subj -match '\(([A-Z0-9]{10})\)' -or $subj -match '([A-Z0-9]{10})') {
      if ($subj -match 'Apple|iPhone|Developer|Distribution') {
        Add "  >>> TEAM ID TROUVE : $($Matches[1]) <<<"
        $script:found = $true
      }
    }
  }
}
if (-not $found) { Add "  (aucun certificat Apple avec Team ID)" }
Add ""

# 2. Fichiers AltServer / AltStore / Apple
Add "--- FICHIERS AltServer / Apple ---"
$roots = @(
  "$env:LOCALAPPDATA\AltServer",
  "$env:APPDATA\AltServer",
  "$env:LOCALAPPDATA\Programs\AltServer",
  "$env:ProgramFiles\AltServer",
  "${env:ProgramFiles(x86)}\AltServer",
  "$env:LOCALAPPDATA\AltStore",
  "$env:APPDATA\Apple Computer",
  "$env:LOCALAPPDATA\Apple Computer"
)
foreach ($root in $roots) {
  if (-not (Test-Path $root)) { continue }
  Add "  Dossier : $root"
  Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -lt 5MB } |
    ForEach-Object {
      try {
        $c = [IO.File]::ReadAllText($_.FullName)
        if ($c -match 'TeamIdentifier|teamId|DEVELOPMENT_TEAM|ApplicationIdentifierPrefix') {
          Add "  FICHIER INTERESSANT : $($_.FullName)"
          if ($c -match '([A-Z0-9]{10})') { Add "  >>> TEAM ID possible : $($Matches[1]) <<<" }
        }
      } catch {}
    }
}
Add ""

# 3. .mobileprovision et .ipa sur Bureau / Downloads / Desktop debien
Add "--- IPA / mobileprovision ---"
$search = @(
  "$env:USERPROFILE\Desktop",
  "$env:USERPROFILE\Downloads",
  "C:\Users\BunnY\Desktop"
)
foreach ($dir in $search) {
  if (-not (Test-Path $dir)) { continue }
  Get-ChildItem $dir -Recurse -Include "*.mobileprovision","*.ipa" -ErrorAction SilentlyContinue | ForEach-Object {
    Add "  Trouve : $($_.FullName)"
  }
}
Add ""

Add "=== FIN ==="
Add ""
Add "Si TEAM ID trouve ci-dessus -> GitHub secret APPLE_TEAM_ID"
Add "Sinon -> certmgr.msc -> Personnel -> Certificats -> Apple Development"
Add "Sinon -> iPhone : Reglages -> General -> Gestion VPN et appareil -> App developpeur"

$lines | Set-Content $out -Encoding UTF8
Add ""
Add "Resultat sauvegarde : $out" -ForegroundColor Green