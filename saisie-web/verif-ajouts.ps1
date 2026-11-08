# SAISIE WEB PROVISOIRE (dossier saisie-web/ : a retirer quand les mails passeront par n8n, voir AJOUTS-MAIL.md).
# Verifie ajouts.json avant fusion (workflow saisie-web-verif.yml, ou a la main).
# Un fichier invalide serait ignore EN SILENCE par fetch-agenda.ps1 (les rendez-vous mail disparaitraient) :
# ici il fait echouer la verification (croix rouge sur la Pull Request).
# Usage : powershell -NoProfile -ExecutionPolicy Bypass -File .\saisie-web\verif-ajouts.ps1 [-Fichier ajouts.json]
#   -Base : version de reference (celle en ligne) pour lister les rendez-vous ajoutes / supprimes / modifies.
#   -Resume : fichier Markdown ou ecrire ce bilan (GITHUB_STEP_SUMMARY sur GitHub).
param([string]$Fichier = (Join-Path (Split-Path $PSScriptRoot) 'ajouts.json'), [string]$Base = '', [string]$Resume = '')

$errs = @(); $warns = @()
$fr = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
$today = (Get-Date).Date
$allowed = @('t', 'u', 'd', 'h', 'g', 'x')

try {
  $list = Get-Content $Fichier -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Write-Output "ERREUR : $Fichier n'est pas un JSON valide : $($_.Exception.Message)"
  exit 1
}

$seen = @{}; $n = 0
foreach ($a in $list) {
  $n++
  $id = "rendez-vous $n ('$($a.t)')"
  foreach ($k in $a.PSObject.Properties.Name) {
    if ($allowed -notcontains $k) { $errs += "$id : cle inconnue '$k' (cles permises : t u d h g x)" }
  }
  if (-not [string]$a.t) { $errs += "$id : titre (t) manquant" }
  $date = [DateTime]::MinValue
  if (-not [DateTime]::TryParseExact([string]$a.d, 'yyyy-MM-dd', $fr, 'None', [ref]$date)) {
    $errs += "$id : date (d) invalide '$($a.d)' (format attendu AAAA-MM-JJ)"
  } elseif ($date -lt $today) {
    $warns += "$id : date passee ($($a.d)), il sera ignore (a supprimer du fichier)"
  } elseif ($date -gt $today.AddDays(400)) {
    $errs += "$id : date trop lointaine ($($a.d)), erreur d'annee ?"
  }
  $h = [string]$a.h
  if ($h -and $h -notmatch '^\d{2}h\d{2}( - \d{2}h\d{2})?$') {
    $errs += "$id : horaire (h) '$h' invalide (formats : '09h30 - 11h00', '18h00' ou vide)"
  }
  # Communications email : aucun lien publie (suivi, desabonnement...). Le champ u est ignore par le site.
  $text = "$($a.t) $($a.g) $($a.x) $h"
  if ($text -match 'https?://|www\.|\.(fr|com|org|net)/') { $errs += "$id : lien interdit dans le texte (aucun lien publie pour les mails)" }
  if ($text -match '<[a-z/]') { $errs += "$id : balise HTML interdite" }
  if ([string]$a.u) { $warns += "$id : u non vide, il sera ignore (laisser u vide)" }
  $key = "$($a.d)|$($a.t)"
  if ($seen[$key]) { $errs += "$id : doublon (meme date et meme titre)" }
  $seen[$key] = $true
}

# ---------- Bilan lisible : ce qui change par rapport a la version en ligne ----------
function Line($a) {
  $h = if ([string]$a.h) { $a.h } else { 'horaire non pr&eacute;cis&eacute;' }
  $g = if ([string]$a.g) { " - $($a.g)" } else { '' }
  "**$($a.d)** ($h) : **$($a.t)**$g`n  > $($a.x)"
}
$md = @()
if ($Base) {
  $old = @()
  # PS 5.1 : ConvertFrom-Json renvoie le tableau en un seul objet ; le passer par une variable l'enumere
  if (Test-Path $Base) { try { $o = Get-Content $Base -Raw -Encoding UTF8 | ConvertFrom-Json; $old = @($o) } catch { } }
  $new = @($list)
  $key = { param($a) "$($a.d)|$($a.t)" }
  $sig = { param($a) "$($a.d)|$($a.t)|$($a.h)|$($a.g)|$($a.x)" }
  $oldK = @{}; foreach ($a in $old) { $oldK[(& $key $a)] = $a }
  $newK = @{}; foreach ($a in $new) { $newK[(& $key $a)] = $a }
  $add = @($new | Where-Object { -not $oldK[(& $key $_)] })
  $del = @($old | Where-Object { -not $newK[(& $key $_)] })
  $mod = @($new | Where-Object { $o = $oldK[(& $key $_)]; $o -and (& $sig $o) -ne (& $sig $_) })
  $md += "## Ce que cette Pull Request change sur le site (&agrave; relire avant de fusionner)"
  $md += ""
  if (-not ($add.Count + $del.Count + $mod.Count)) { $md += "Aucun rendez-vous ajout&eacute;, supprim&eacute; ou modifi&eacute;." }
  if ($add.Count) { $md += "### Ajout&eacute;s ($($add.Count))"; foreach ($a in $add) { $md += "- $(Line $a)" }; $md += "" }
  if ($mod.Count) { $md += "### Modifi&eacute;s ($($mod.Count))"; foreach ($a in $mod) { $md += "- $(Line $a)"; $md += "  *Avant :* $(Line $oldK[(& $key $a)])" }; $md += "" }
  if ($del.Count) {
    $md += "### Supprim&eacute;s ($($del.Count))"
    foreach ($a in $del) { $p = if ([string]$a.d -lt $today.ToString('yyyy-MM-dd')) { ' *(d&eacute;j&agrave; pass&eacute;)*' } else { '' }; $md += "- $(Line $a)$p" }
    $md += ""
  }
}
$md += "## V&eacute;rification"
$md += ""
if ($errs.Count) { $md += "**ECHEC : ne pas fusionner.**"; foreach ($e in $errs) { $md += "- ERREUR : $e" } }
else { $md += "OK : $n rendez-vous valides." }
foreach ($w in $warns) { $md += "- AVERTISSEMENT : $w" }
if ($Resume) { [IO.File]::AppendAllText($Resume, ($md -join "`n") + "`n", (New-Object Text.UTF8Encoding $false)) }
elseif ($Base) { $md | ForEach-Object { Write-Output $_ } }

foreach ($w in $warns) { Write-Output "AVERTISSEMENT : $w" }
foreach ($e in $errs) { Write-Output "ERREUR : $e" }
if ($errs.Count) { Write-Output "ECHEC : $($errs.Count) erreur(s) dans $Fichier"; exit 1 }
Write-Output "OK : $n rendez-vous valides dans $Fichier"
