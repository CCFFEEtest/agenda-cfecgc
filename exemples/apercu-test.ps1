# SIMULATION - apercu local des "communications email" avec les mails d'exemple.
# Tout le code de simulation est ici, dans exemples\ (jamais publie) : le script principal
# fetch-agenda.ps1 n'en contient aucune trace. Quand les vrais mails arriveront (VPS + n8n
# -> ajouts.json), il suffira de ne plus lancer ce script, ou de supprimer le dossier exemples\.
#
# Ce qu'il fait :
#  1. lance fetch-agenda.ps1 sans ajouts pour connaitre la periode des evenements nationaux ;
#  2. decale les rendez-vous de ajouts-test.json d'un nombre entier de semaines (jours de la
#     semaine et ecarts conserves) pour que le premier tombe au debut de cette periode :
#     ils restent "a venir" quel que soit le mois ;
#  3. relance fetch-agenda.ps1 avec ces ajouts decales -> index.html d'apercu (non publie).
#
# Usage : powershell -NoProfile -ExecutionPolicy Bypass -File .\exemples\apercu-test.ps1

$ErrorActionPreference = 'Stop'
$root    = Split-Path $PSScriptRoot -Parent
$fetch   = Join-Path $root 'fetch-agenda.ps1'
$samples = Join-Path $PSScriptRoot 'ajouts-test.json'
$none    = Join-Path $env:TEMP 'agenda-sans-ajouts.json'   # n'existe pas : passe sans ajouts
$shifted = Join-Path $env:TEMP 'agenda-ajouts-decales.json'
$fr      = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')

# 1. Periode nationale : premier rendez-vous du site, lu dans la page generee
if (Test-Path $none) { Remove-Item $none }
& powershell -NoProfile -ExecutionPolicy Bypass -File $fetch -Ajouts $none
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR : fetch-agenda.ps1 a echoue (code $LASTEXITCODE)"; exit $LASTEXITCODE }
$html = [IO.File]::ReadAllText((Join-Path $root 'index.html'), [Text.Encoding]::UTF8)
$natJson = [regex]::Match($html, 'window\.EVENTS = (\[.*?\]);').Groups[1].Value
$natList = $natJson | ConvertFrom-Json
$start = (@(foreach ($e in $natList) { [DateTime]::ParseExact($e.d, 'yyyy-MM-dd', $fr) }) | Measure-Object -Minimum).Minimum

# 2. Decalage des exemples par semaines entieres
$raw  = [IO.File]::ReadAllText($samples, [Text.Encoding]::UTF8)
$list = $raw | ConvertFrom-Json
$first = (@(foreach ($a in $list) { [DateTime]::ParseExact($a.d, 'yyyy-MM-dd', $fr) }) | Measure-Object -Minimum).Minimum
$shift = 7 * [Math]::Ceiling(($start - $first).TotalDays / 7)
# Remplacement texte des dates (evite ConvertTo-Json de PS 5.1 qui deforme les tableaux)
$out = [regex]::Replace($raw, '"d":\s*"(\d{4}-\d{2}-\d{2})"', {
  param($m) '"d": "' + [DateTime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd', $fr).AddDays($shift).ToString('yyyy-MM-dd') + '"'
})
[IO.File]::WriteAllText($shifted, $out, (New-Object Text.UTF8Encoding $false))

# 3. Apercu avec les exemples decales
& powershell -NoProfile -ExecutionPolicy Bypass -File $fetch -Ajouts $shifted
$code = $LASTEXITCODE
Remove-Item $shifted -ErrorAction SilentlyContinue
Write-Host ("Apercu test : exemples decales de {0} jours (premier le {1}, debut national le {2})" -f $shift,
  $first.AddDays($shift).ToString('yyyy-MM-dd'), $start.ToString('yyyy-MM-dd'))
exit $code
