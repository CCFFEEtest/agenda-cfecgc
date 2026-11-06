# Recupere les rendez-vous a venir de l'agenda de cfecgc-orange.org
# et genere index.html (timeline + planning du jour + cartouches).
# Lance 3 fois par jour (8h, 14h, 18h heure de Paris) par GitHub Actions.
# -Ajouts : fichier JSON de rendez-vous ajoutes a la main ou depuis des mails
# (memes cles que window.EVENTS : t, d, h, g, x, u). Ignore s'il n'existe pas.
param([string]$Ajouts = (Join-Path $PSScriptRoot 'ajouts.json'))

$ErrorActionPreference = 'Stop'
$source  = 'https://www.cfecgc-orange.org/evenements/'
$outFile = Join-Path $PSScriptRoot 'index.html'
$logFile = Join-Path $PSScriptRoot 'fetch.log'
$fr      = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Log($msg) {
  Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
}
function Clean($html) {
  $t = [regex]::Replace($html, '<[^>]+>', ' ')
  $t = [Net.WebUtility]::HtmlDecode($t)
  return ([regex]::Replace($t, '\s+', ' ')).Trim()
}
function Enc($s) { [Net.WebUtility]::HtmlEncode($s) }
# Heure de Paris, meme sur une machine reglee en UTC (GitHub Actions)
function ParisNow { [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date).ToUniversalTime(), 'Romance Standard Time') }

$wc = New-Object Net.WebClient
$wc.Encoding = [Text.Encoding]::UTF8

# ---------- Evenements a venir (page /evenements/, plusieurs pages) ----------
$events = New-Object System.Collections.ArrayList
$seenEv = @{}
$today  = (ParisNow).Date
try {
  for ($p = 1; $p -le 5; $p++) {
    $url = if ($p -eq 1) { $source } else { "${source}page/$p/" }
    # WebClient efface ses en-tetes apres chaque requete, et le site renvoie 403 sans User-Agent
    $wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AgendaBot'
    try { $eh = $wc.DownloadString($url) } catch {
      if ($p -eq 1) { Log "ERREUR telechargement ($url) : $($_.Exception.Message) (page precedente conservee)"; exit 1 }
      Log "AVERTISSEMENT ($url) : $($_.Exception.Message)"; break
    }
    $foundFuture = $false
    foreach ($m in [regex]::Matches($eh, '(?s)<article\b.*?</article>')) {
      $b = $m.Value
      $a = [regex]::Match($b, '(?s)<h[23][^>]*>\s*<a\s+href="([^"]+)"[^>]*>(.*?)</a>')
      $d = [regex]::Match($b, '<span class="date">(.*?)</span>')
      if (-not $a.Success -or -not $d.Success) { continue }
      $dateTxt = Clean $d.Groups[1].Value
      $date = [DateTime]::MinValue
      if (-not [DateTime]::TryParseExact($dateTxt, 'd MMMM yyyy', $fr, 'None', [ref]$date)) { continue }
      if ($date -lt $today) { continue }
      $foundFuture = $true
      $link = $a.Groups[1].Value
      if ($seenEv.ContainsKey($link)) { continue }
      $seenEv[$link] = $true
      $tm  = [regex]::Match($b, '<span class="time">(.*?)</span>')
      $tag = [regex]::Match($b, '<span class="tag">(.*?)</span>')
      [void]$events.Add([pscustomobject]@{
        Title = Clean $a.Groups[2].Value; Url = $link; Date = $date
        Time  = $(if ($tm.Success) { Clean $tm.Groups[1].Value } else { '' })
        Tag   = $(if ($tag.Success) { Clean $tag.Groups[1].Value } else { '' })
        Extract = $(if ($x = [regex]::Match($b, '(?s)<p class="extract">(.*?)</p>')) { if ($x.Success) { (Clean $x.Groups[1].Value) -replace '\s*\[\S*\]\s*$', '...' } else { '' } })
      })
    }
    if (-not $foundFuture) { break }
  }
} catch { Log "ERREUR evenements : $($_.Exception.Message) (page precedente conservee)"; exit 1 }
$events = @($events | Sort-Object Date, Time)
if ($events.Count -eq 0) {
  Log "ERREUR : aucun rendez-vous a venir trouve (la mise en page du site a peut-etre change). Page precedente conservee."
  exit 2
}

# ---------- Rendez-vous ajoutes (hors site, ex. recus par mail) ----------
$added = 0
if (Test-Path $Ajouts) {
  try {
    # PS 5.1 : ConvertFrom-Json renvoie le tableau en un seul objet ; le passer par une variable l'enumere
    $list = Get-Content $Ajouts -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($a in $list) {
      $date = [DateTime]::MinValue
      if (-not [DateTime]::TryParseExact([string]$a.d, 'yyyy-MM-dd', $fr, 'None', [ref]$date) -or -not $a.t) { continue }
      if ($date -lt $today) { continue }
      if ($events | Where-Object { $_.Date -eq $date -and $_.Title -eq $a.t }) { continue }
      # Communications email : AUCUN lien publie (ni suivi, ni desabonnement, ni mailto). La carte
      # affiche a la place "voir mail" + un lien vers la page d'abonnement de la CFE-CGC Orange.
      if ([string]$a.u) { Log "INFO ajouts : lien ignore pour '$($a.t)' (aucun lien publie pour les communications email)" }
      $events += [pscustomobject]@{ Title = [string]$a.t; Url = ''; Date = $date; Time = [string]$a.h
                                    Tag = [string]$a.g; Extract = [string]$a.x; Added = $true }
      $added++
    }
    $events = @($events | Sort-Object Date, Time)
  } catch { Log "AVERTISSEMENT ajouts ($Ajouts) : $($_.Exception.Message) (ajouts ignores)" }
}

# ---------- Lieux (carte) ----------
# Le site ne donne pas de champ "lieu" : on le deduit du titre / libelle / description, dans cet ordre :
# site Orange connu (lieux-orange.csv) > adresse postale > [Ville] > "Ville : ..." > departement
# (chef-lieu, departements.csv). Sinon : Teams, a distance, ou lieu inconnu (pave "ordinateur").
# Geocodage : api-adresse.data.gouv.fr (service public gratuit), un appel par lieu distinct.
function Norm($s) {
  $d = ([string]$s).Normalize([Text.NormalizationForm]::FormD)
  $d = [regex]::Replace($d, '\p{Mn}', '')
  return ([regex]::Replace($d.ToLowerInvariant(), "[^a-z0-9]+", ' ')).Trim()
}
function ReadCsv($name) {
  $p = Join-Path $PSScriptRoot $name
  if (Test-Path $p) { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Csv -Delimiter ';' }
  return @()
}
$sites = @(ReadCsv 'lieux-orange.csv')
$depts = @{}
foreach ($r in (ReadCsv 'departements.csv')) { $depts[(Norm $r.departement)] = $r.'chef-lieu' }
$geoCache = @{}
function Geo {
  param([Parameter(Position = 0)][string]$q, [switch]$City)
  $k = "$City|$q"
  if ($geoCache.ContainsKey($k)) { return $geoCache[$k] }
  $res = $null
  try {
    $url = 'https://api-adresse.data.gouv.fr/search/?limit=1&q=' + [uri]::EscapeDataString($q) + $(if ($City) { '&type=municipality' } else { '' })
    $wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AgendaBot'
    $f = @(($wc.DownloadString($url) | ConvertFrom-Json).features)[0]
    if ($f) {
      $town = [string]$f.properties.city
      # Ville : le nom trouve doit figurer dans la recherche (evite "Rendez-vous de l'epargne" -> une commune au hasard)
      $ok = if ($City) { (' ' + (Norm $q) + ' ').Contains(' ' + (Norm $town) + ' ') } else { $f.properties.score -ge 0.5 }
      if ($ok) { $res = [pscustomobject]@{ Lat = [math]::Round($f.geometry.coordinates[1], 5); Lon = [math]::Round($f.geometry.coordinates[0], 5); City = $town } }
    }
  } catch { Log "AVERTISSEMENT geocodage ($q) : $($_.Exception.Message)" }
  $geoCache[$k] = $res
  return $res
}
function Locate($e) {
  $txt = "$($e.Title) | $($e.Tag) | $($e.Extract)"
  foreach ($s in $sites) {
    if ($txt -match [regex]::Escape($s.motif)) { $g = Geo $s.recherche; if ($g) { return @{ l = $s.nom; p = @($g.Lat, $g.Lon) } } }
  }
  $m = [regex]::Match($txt, '\d{1,4}\s*(bis|ter)?,?\s+(rue|avenue|av\.|boulevard|bd|place|all\u00e9e|quai|chemin|route|cours|impasse)\s[^,;|]{2,60}?,?\s\d{5}\s+[^\s,.;|]+(-[^\s,.;|]+)*', 'IgnoreCase')
  if ($m.Success) { $g = Geo $m.Value; if ($g) { return @{ l = $m.Value; p = @($g.Lat, $g.Lon) } } }
  $m = [regex]::Match($e.Title, '^\s*\[([^\]]{2,40})\]')
  if ($m.Success) { $g = Geo $m.Groups[1].Value -City; if ($g) { return @{ l = $g.City; p = @($g.Lat, $g.Lon) } } }
  $m = [regex]::Match($e.Title, '^\s*([^:\[\]]{2,40}?)\s*:')
  if ($m.Success) { $g = Geo $m.Groups[1].Value -City; if ($g) { return @{ l = $m.Groups[1].Value.Trim(); p = @($g.Lat, $g.Lon) } } }
  $m = [regex]::Match($txt, 'D\u00e9partement\s+(du|de la|de l[''\u2019]|des|de)\s*([^:,.;|]+)', 'IgnoreCase')
  if ($m.Success) {
    $n = Norm $m.Groups[2].Value
    $hit = $depts.Keys | Where-Object { $n -eq $_ -or $n.StartsWith("$_ ") } | Sort-Object Length -Descending | Select-Object -First 1
    if ($hit) { $g = Geo $depts[$hit] -City; if ($g) { return @{ l = "$($g.City) (chef-lieu, $($m.Groups[2].Value.Trim()))"; p = @($g.Lat, $g.Lon) } } }
  }
  if ($txt -match '(?i)\bteams\b') { return @{ v = 'teams' } }
  if ($txt -match '(?i)webinaire|visio|en ligne|\u00e0 distance|distanciel|t\u00e9l\u00e9phone|site de vote') { return @{ v = 'distance' } }
  return @{ v = 'inconnu' }
}
foreach ($e in $events) { $e | Add-Member -NotePropertyName Loc -NotePropertyValue (Locate $e) -Force }

# ---------- Rendez-vous sur plusieurs jours ----------
# Cherche dans le titre et la description une periode qui COMMENCE le jour du rendez-vous et finit plus tard :
#   "du lundi 7/12/2026 - 14h00 au jeudi 10/12/2026", "du 7 au 10 decembre", "du 7/12 au 10/12",
#   "07/12/26 - 10/12/26", "7 au 10 decembre", "du 7 decembre 14h au 8 decembre 12h",
#   "du 7 decembre 2026 au 15 janvier 2027", "les 7, 8 et 9 decembre", "jusqu'au 10 decembre",
#   "pendant 3 jours", "du lundi au jeudi".
# Resultat : nombre de jours en plus du premier (0 si rien, max 31) -> "+N jours", planning jusqu'a 18h, "4h+".
$months = @{ janvier = 1; fevrier = 2; mars = 3; avril = 4; mai = 5; juin = 6; juillet = 7; aout = 8; septembre = 9; octobre = 10; novembre = 11; decembre = 12 }
$wdays  = @{ lundi = 1; mardi = 2; mercredi = 3; jeudi = 4; vendredi = 5; samedi = 6; dimanche = 0 }
$reWd   = '(?:(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+)?'
$reMn   = '(?:janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|decembre)'
# Une date : 7/12, 07/12/26, 7/12/2026, ou 7, 1er, 7 decembre, 7 decembre 2026 (un nombre seul n'est pas suivi de h, :, / ou d'un chiffre)
$reDate = "\b(?:(?<nd>\d{1,2})/(?<nm>\d{1,2})(?:/(?<ny>\d{4}|\d{2}))?|(?<td>\d{1,2})(?:er)?(?!\s*h|\s*:|\d|/)(?:\s+(?<tm>$reMn))?(?:\s+(?<ty>\d{4}))?)\b"
# Ce qui peut separer deux dates d'une meme periode : heure eventuelle puis "au", "a", "jusqu'au", "-", "," ou "et"
$reLink = "^\s*(?:[-,]\s*)?(?:\d{1,2}\s*h\s*\d{0,2}\s*)?(?:-|,|et|au|a|jusqu'?au)\s*$reWd$"
function LowText($s) {
  $d = ([string]$s).Normalize([Text.NormalizationForm]::FormD)
  $d = [regex]::Replace($d, '\p{Mn}', '').ToLowerInvariant()
  $d = [regex]::Replace($d, '[\u2013\u2014]', '-').Replace([string][char]0x2019, "'")
  return [regex]::Replace($d, '\s+', ' ')
}
function ExtraDays($e) {
  $t = LowText "$($e.Title) . $($e.Extract)"
  $start = $e.Date.Date
  $best = 0
  # Dates trouvees dans le texte, dans l'ordre
  $ds = @(foreach ($m in [regex]::Matches($t, $reDate)) {
    if ($m.Groups['nd'].Success) {
      [pscustomobject]@{ I = $m.Index; E = $m.Index + $m.Length; D = [int]$m.Groups['nd'].Value; M = [int]$m.Groups['nm'].Value
                         Y = $(if ($m.Groups['ny'].Success) { $y = [int]$m.Groups['ny'].Value; if ($y -lt 100) { 2000 + $y } else { $y } } else { 0 }) }
    } else {
      [pscustomobject]@{ I = $m.Index; E = $m.Index + $m.Length; D = [int]$m.Groups['td'].Value
                         M = $(if ($m.Groups['tm'].Success) { $months[$m.Groups['tm'].Value] } else { 0 })
                         Y = $(if ($m.Groups['ty'].Success) { [int]$m.Groups['ty'].Value } else { 0 }) }
    }
  })
  # Chaines de dates reliees ("du A au B", "les A, B et C") : le premier element doit etre le jour du rendez-vous
  for ($i = 0; $i -lt $ds.Count; $i++) {
    $chain = @($ds[$i]); $j = $i
    while ($j + 1 -lt $ds.Count -and $t.Substring($ds[$j].E, $ds[$j + 1].I - $ds[$j].E) -match $reLink) { $j++; $chain += $ds[$j] }
    if ($chain.Count -lt 2) { continue }
    # Mois / annee manquants : repris de la date suivante (ou precedente), sinon ceux du rendez-vous
    $mon = $start.Month; $yr = $start.Year
    for ($k = $chain.Count - 1; $k -ge 0; $k--) { if ($chain[$k].M) { $mon = $chain[$k].M; break } }
    for ($k = $chain.Count - 1; $k -ge 0; $k--) { if ($chain[$k].Y) { $yr = $chain[$k].Y; break } }
    $a = $chain[0]
    $am = $(if ($a.M) { $a.M } else { $mon }); $ay = $(if ($a.Y) { $a.Y } else { $start.Year })
    if ($a.D -ne $start.Day -or $am -ne $start.Month -or $ay -ne $start.Year) { continue }
    $z = $chain[$chain.Count - 1]
    $zm = $(if ($z.M) { $z.M } else { $am }); $zy = $(if ($z.Y) { $z.Y } else { $yr })
    try { $end = New-Object DateTime $zy, $zm, $z.D } catch { continue }
    if ($end -le $start) { try { $end = $end.AddYears(1) } catch { continue } }   # "du 28 decembre au 3 janvier"
    $n = ($end - $start).Days
    if ($n -gt $best -and $n -le 31) { $best = $n }
  }
  # "jusqu'au [jour] 10 decembre" / "jusqu'au 10/12"
  foreach ($m in [regex]::Matches($t, "jusqu'?au\s+$reWd$reDate")) {
    $x = [regex]::Match($m.Value, $reDate)
    if ($x.Groups['nd'].Success) { $dd = [int]$x.Groups['nd'].Value; $mm = [int]$x.Groups['nm'].Value }
    elseif ($x.Groups['tm'].Success) { $dd = [int]$x.Groups['td'].Value; $mm = $months[$x.Groups['tm'].Value] }
    else { $dd = [int]$x.Groups['td'].Value; $mm = $start.Month }
    try { $end = New-Object DateTime $start.Year, $mm, $dd } catch { continue }
    if ($end -lt $start) { $end = $end.AddYears(1) }
    $n = ($end - $start).Days
    if ($n -gt $best -and $n -le 31) { $best = $n }
  }
  # "pendant 3 jours", "sur 2 jours"
  $m = [regex]::Match($t, '\b(?:pendant|sur|durant)\s+(\d{1,2})\s+jours\b')
  if ($m.Success) { $n = [int]$m.Groups[1].Value - 1; if ($n -gt $best -and $n -le 31) { $best = $n } }
  # "du lundi au jeudi" (sans dates) : seulement en dernier recours, si le rendez-vous tombe bien le premier
  # jour cite, et pas pour des horaires d'ouverture ("assistance du lundi au vendredi de 9h a 18h")
  $m = [regex]::Match($t, '\bdu\s+(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+au\s+(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b(?!\s*(?:,\s*)?(?:de|entre)\s+\d{1,2}\s*h)')
  if ($best -eq 0 -and $m.Success -and $wdays[$m.Groups[1].Value] -eq [int]$start.DayOfWeek) {
    $n = ($wdays[$m.Groups[2].Value] - $wdays[$m.Groups[1].Value] + 7) % 7
    if ($n -gt $best) { $best = $n }
  }
  return $best
}
foreach ($e in $events) { $e | Add-Member -NotePropertyName Days -NotePropertyValue (ExtraDays $e) -Force }

# ---------- Generation de la page ----------
# Donnees de la timeline (rendu en JavaScript dans la page)
$evData = @($events | ForEach-Object {
  $o = [ordered]@{ t = $_.Title; u = $_.Url; d = $_.Date.ToString('yyyy-MM-dd'); h = $_.Time; g = $_.Tag; x = $_.Extract }
  if ($_.Added) { $o.a = 1 }
  if ($_.Loc.p) { $o.l = $_.Loc.l; $o.p = $_.Loc.p } else { $o.v = $_.Loc.v }
  if ($_.Days) { $o.j = $_.Days }
  $o
})
$evJson = ConvertTo-Json -InputObject $evData -Compress -Depth 3
$eventsHtml = @"
  <section class="tl-card">
    <div class="tl">
      <button type="button" class="tl-arrow" id="prev"><span class="pg" id="pgPrev"></span><span class="ar"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5M11 6l-6 6 6 6"/></svg></span><span class="lb">plus t&ocirc;t</span></button>
      <ol class="tl-days" id="tlDays"></ol>
      <button type="button" class="tl-arrow" id="next"><span class="pg" id="pgNext"></span><span class="ar"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg></span><span class="lb">plus tard</span></button>
    </div>
    <div class="tl-cards" id="tlCards"></div>
  </section>
  <section class="recap" id="calendrier">
    <div class="hrow"><h2>Vue calendrier</h2><div class="filters" role="group" aria-label="Afficher selon l&#39;origine"><button type="button" class="flt" data-f="nat" aria-pressed="true">calendrier national</button><button type="button" class="flt flt-mail" data-f="mail" aria-pressed="true">communications email</button></div></div>
    <div class="months" id="months"></div>
  </section>
  <section class="recap" id="carte">
    <div class="hrow"><h2>Carte des &eacute;v&eacute;nements <span class="hspan" id="mapSpan"></span></h2><div class="filters" role="group" aria-label="Afficher selon l&#39;origine"><button type="button" class="flt" data-f="nat" aria-pressed="true">calendrier national</button><button type="button" class="flt flt-mail" data-f="mail" aria-pressed="true">communications email</button></div></div>
    <div class="mapcard">
      <div class="mapwrap"><div class="mvirt" id="mapVirt" role="group" aria-label="Type de lieu"></div>
        <div id="map" role="region" aria-label="Carte des rendez-vous par lieu"></div></div>
      <div class="mdetail" id="mapDetail" hidden></div>
    </div>
  </section>
  <script>window.EVENTS = $evJson;</script>
"@
$now   = ParisNow
$stamp = $now.ToString("dddd d MMMM yyyy '&agrave;' HH'h'mm", $fr)
# Version des fichiers statiques : change a chaque generation, pour que les navigateurs (Safari iPhone)
# rechargent style.css et wip.png au lieu de garder une ancienne copie en cache
$ver = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmm")
# Prochain passage planifie (7h, 14h, 19h heure de Paris, voir .github/workflows/update.yml)
$slot = @(8, 14, 18) | Where-Object { $_ -gt $now.Hour } | Select-Object -First 1
$next = if ($slot) { "${slot}h00" } else { 'demain 8h00' }

$page = @"
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="900">
<title>Agenda CFE-CGC Orange FC</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css">
<link rel="stylesheet" href="style.css?v=$ver">
<script>
  (function () {
    var t = null;
    try { t = localStorage.getItem('theme'); } catch (e) {}
    if (t !== 'light' && t !== 'dark') t = (window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', t);
  })();
</script>
</head>
<body>
<div class="frame">
<div class="banner"><h1><a href="./">Agenda CFE-CGC Orange FC</a></h1><img class="wip" src="wip.png?v=$ver" alt="WIP : test en cours" title="Site en cours de test" width="132" height="48"><button type="button" class="bn-ico" id="themeBtn" title="Changer de th&egrave;me" aria-label="Changer de th&egrave;me"><svg class="ico-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4.5"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg><svg class="ico-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z"/></svg></button></div>
<script>
  (function () {
    var root = document.documentElement, btn = document.getElementById('themeBtn');
    function label() {
      var dark = root.getAttribute('data-theme') === 'dark';
      btn.title = dark ? 'Passer en th\u00e8me clair' : 'Passer en th\u00e8me sombre';
      btn.setAttribute('aria-label', btn.title);
    }
    btn.addEventListener('click', function () {
      var t = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', t);
      try { localStorage.setItem('theme', t); } catch (e) {}
      label();
    });
    if (window.matchMedia) {
      var mq = matchMedia('(prefers-color-scheme: dark)'), onSys = function (e) {
        var saved = null;
        try { saved = localStorage.getItem('theme'); } catch (x) {}
        if (!saved) { root.setAttribute('data-theme', e.matches ? 'dark' : 'light'); label(); }
      };
      if (mq.addEventListener) mq.addEventListener('change', onSys); else if (mq.addListener) mq.addListener(onSys);
    }
    label();
  })();
</script>
<div class="wrap">
  <header>
    <p class="sub">$($events.Count - $added) rendez-vous &agrave; venir sur <a href="$source" target="_blank" rel="noopener">cfecgc-orange.org</a>$(if ($added) { " + $added issu$(if ($added -gt 1) { 's' }) de communications email" }) &middot; mis &agrave; jour $stamp</p>
    <div class="hrow"><h2>Prochains &eacute;v&eacute;nements</h2><div class="filters" role="group" aria-label="Afficher selon l&#39;origine"><button type="button" class="flt" data-f="nat" aria-pressed="true">calendrier national</button><button type="button" class="flt flt-mail" data-f="mail" aria-pressed="true">communications email</button></div></div>
  </header>
$eventsHtml
  <script>
  // Outils communs a la timeline et au calendrier : rendu des cartes, origine, filtre partage
  window.AG = (function () {
    var COLORS = ['#8fae8a', '#7fa6a6', '#8da4c9', '#a98cad', '#c98b7a'];
    var fL = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    function esc(s) { var d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
    function pd(s) { var p = s.split('-'); return new Date(+p[0], p[1] - 1, +p[2]); }
    // Lien vers le detail ; mailto: sans target=_blank (sinon onglet vide ou rien du tout)
    function lnk(e) { return !e.u ? '' : /^mailto:/i.test(e.u) ? ' href="' + esc(e.u) + '"' : ' href="' + esc(e.u) + '" target="_blank" rel="noopener"'; }
    // Origine : site scanne (calendrier national) ou communication recue par mail (e.a)
    function isNat(g) { return String(g || '').trim().toLowerCase() === 'calendrier national'; }
    function srcTag(e) {
      return '<span class="src' + (e.a ? ' src-mail' : '') + '">' + (e.a ? 'communication email' : 'calendrier national') + '</span>'
        + (ended(e) ? '<span class="src src-end">&eacute;v&eacute;nement termin&eacute;</span>' : '');
    }
    // Horaire affiche. Plusieurs jours (e.j) : debut -> 18h00 puis "(+N jours)"
    function timeText(e) {
      if (!e.h) return 'Horaire non pr&eacute;cis&eacute;';
      if (!e.j) return esc(e.h);
      var s = /\d{1,2}\s*h\s*\d{0,2}/i.exec(e.h);
      return (s ? esc(s[0]) + ' - 18h00' : esc(e.h)) + ' (+' + e.j + (e.j > 1 ? ' jours' : ' jour') + ')';
    }
    function dkey(n) { return n.getFullYear() + '-' + ('0' + (n.getMonth() + 1)).slice(-2) + '-' + ('0' + n.getDate()).slice(-2); }
    // Termine : jour passe, ou aujourd'hui et heure de fin atteinte (sans heure de fin : heure de debut ;
    // sans aucun horaire : fin de journee). Plusieurs jours : seulement apres le dernier jour.
    // Recalcule a chaque affichage (la page se recharge toutes les 15 min).
    function ended(e) {
      var n = new Date(), k = dkey(n);
      if (e.j) { var p = e.d.split('-'); return dkey(new Date(+p[0], p[1] - 1, +p[2] + e.j)) < k; }
      if (e.d !== k) return e.d < k;
      var t = (e.h || '').match(/\d{1,2}\s*h\s*\d{0,2}/gi);
      if (!t) return false;
      var m = /(\d{1,2})\s*h\s*(\d{0,2})/i.exec(t[t.length - 1]);
      return n.getHours() * 60 + n.getMinutes() >= +m[1] * 60 + (+(m[2] || 0));
    }
    // Cartouche d'un rendez-vous (timeline et liste du jour du calendrier)
    // Page d'abonnement aux communications (bouton "S'abonner" du site cfecgc-orange.org)
    var SUBSCRIBE = 'https://odyssee.cfecgc-orange.org/com/page/1387';
    // num : numero affiche devant le titre ; noDate : date omise (listes deja groupees sous le titre du jour)
    function card(e, num, noDate) {
      // Communication email : la carte n'est pas un lien (un lien ne peut pas en contenir un autre)
      var tag = e.a || !e.u ? 'div' : 'a';
      return '<' + tag + ' class="ev-card' + (tag === 'div' ? ' nolink' : '') + (ended(e) ? ' ended' : '') + '" data-k="' + e.i + '" style="--ev-bd:' + e.c + '"' + (tag === 'a' ? lnk(e) : '') + '>'
        + '<span class="when">' + (noDate ? '' : '<b>' + esc(fL.format(pd(e.d))) + '</b>') + '<span>' + timeText(e) + '</span>'
        + (e.g && !isNat(e.g) ? '<span>' + esc(e.g) + '</span>' : '') + srcTag(e) + '</span>'
        + '<span class="ttl">' + (num ? '<span class="evn">' + num + '</span>' : '') + esc(e.t) + '</span>'
        + (e.x ? '<p>' + esc(e.x) + '</p>' : '')
        + (e.a ? '<span class="more">&rarr; voir mail (<a href="' + SUBSCRIBE + '" target="_blank" rel="noopener">s&rsquo;inscrire</a>)</span>'
               : e.u ? '<span class="more">Voir le d&eacute;tail &rarr;</span>' : '') + '</' + tag + '>';
    }
    function startH(e) { var m = /(\d{1,2})\s*h\s*(\d{2})?/i.exec(e.h || ''); return m ? +m[1] * 60 + (+(m[2] || 0)) : 0; }
    // Couleur par ordre de debut dans la journee (meme regle partout)
    function colorDay(list) { list.forEach(function (e, i) { e.c = COLORS[i % COLORS.length]; e.i = i; }); return list; }
    // Listes (calendrier, carte) : toutes les cartes en vert clair, sans date (deja en titre du jour)
    var LIST_GREEN = '#9fd19a';
    function listCards(list, start) { return '<div class="cards">' + list.map(function (e, i) { e.c = LIST_GREEN; e.i = i; return card(e, 0, true); }).join('') + '</div>'; }

    // Filtre par origine, partage par les deux sections et memorise sur l'appareil
    var KEY = 'agFiltre', f = { nat: true, mail: true }, subs = [];
    try { var s = JSON.parse(localStorage.getItem(KEY) || 'null'); if (s && (s.nat || s.mail)) f = { nat: !!s.nat, mail: !!s.mail }; } catch (x) {}
    var hasMail = (window.EVENTS || []).some(function (e) { return e.a; });
    if (!hasMail) f = { nat: true, mail: true };
    function shown(e) { return e.a ? f.mail : f.nat; }
    function paint() {
      document.querySelectorAll('.filters').forEach(function (box) {
        box.hidden = !hasMail;
        box.querySelectorAll('[data-f]').forEach(function (b) {
          var on = f[b.getAttribute('data-f')];
          b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false');
        });
      });
    }
    document.addEventListener('click', function (ev) {
      var b = ev.target.closest('.filters [data-f]'); if (!b) return;
      var k = b.getAttribute('data-f'), n = { nat: f.nat, mail: f.mail };
      n[k] = !n[k];
      if (!n.nat && !n.mail) return; // au moins une origine reste affichee
      f = n;
      try { localStorage.setItem(KEY, JSON.stringify(f)); } catch (x) {}
      paint(); subs.forEach(function (fn) { fn(); });
    });
    paint();
    return { esc: esc, pd: pd, lnk: lnk, card: card, listCards: listCards, ended: ended, startH: startH, colorDay: colorDay, shown: shown, fL: fL,
             onChange: function (fn) { subs.push(fn); } };
  })();
  </script>
  <script>
  // Timeline : jours ouvres avec rendez-vous (+ aujourd'hui), planning du jour et cartouches
  (function () {
    var ALL = window.EVENTS || [], daysEl = document.getElementById('tlDays'), AG = window.AG;
    if (!daysEl || !ALL.length) return;
    var esc = AG.esc, pd = AG.pd;
    var now = new Date(), todayKey = now.getFullYear() + '-' + ('0' + (now.getMonth() + 1)).slice(-2) + '-' + ('0' + now.getDate()).slice(-2);
    function hm(s) { var m = /(\d{1,2})\s*h\s*(\d{2})?/i.exec(s || ''); return m ? +m[1] + (+(m[2] || 0)) / 60 : null; }
    ALL.forEach(function (e) {
      var p = (e.h || '').split('-'); e.s = hm(p[0]); e.e = hm(p[1]);
      if (e.j && e.s != null && e.s < 18) e.e = 18; // plusieurs jours : bloc du debut jusqu'a 18h
      e.dur = '';
      if (e.s != null && e.e != null && e.e > e.s) {
        var mn = Math.round((e.e - e.s) * 60), hh = Math.floor(mn / 60), mm = mn % 60;
        e.dur = hh ? hh + 'h' + (mm ? (mm < 10 ? '0' : '') + mm : '') : mm + 'min';
        if (e.j) e.dur += '+'; // se poursuit les jours suivants
      }
      // sans horaire : valeurs de tri seulement, aucun bloc dans le planning
      e.nt = e.s == null; if (e.nt) { e.s = 9; e.e = 10; }
      if (e.e == null || e.e <= e.s) e.e = e.s + 1;
    });
    var fD = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
    var EV = [], dates = [], sel = 0, page = 0, per = 5, selDate = null;

    function perPage() { return window.innerWidth < 600 ? 3 : 5; }
    // Recalcule les jours affiches selon le filtre, en gardant si possible le jour choisi
    function rebuild() {
      EV = ALL.filter(AG.shown);
      dates = [];
      EV.forEach(function (e) { var w = pd(e.d).getDay(); if (w > 0 && w < 6 && dates.indexOf(e.d) < 0) dates.push(e.d); });
      if (now.getDay() > 0 && now.getDay() < 6 && dates.indexOf(todayKey) < 0) dates.push(todayKey); // aujourd'hui toujours present
      dates.sort();
      var want = selDate || todayKey;
      sel = 0;
      for (var i = 0; i < dates.length; i++) { if (dates[i] >= want) { sel = i; break; } }
      per = perPage(); page = Math.floor(sel / per);
    }
    function render() {
      if (!dates.length) { daysEl.innerHTML = ''; document.getElementById('tlCards').innerHTML = ''; return; }
      per = perPage();
      var pages = Math.ceil(dates.length / per);
      if (page > pages - 1) page = pages - 1;
      var from = page * per, slice = dates.slice(from, from + per), html = '';
      selDate = dates[sel];
      daysEl.style.setProperty('--n', per);
      slice.forEach(function (d, k) {
        var n = EV.filter(function (e) { return e.d === d; }).length;
        html += '<li class="' + (from + k === sel ? 'sel' : '') + (d === todayKey ? ' is-today' : '') + '">'
          + '<button type="button" data-i="' + (from + k) + '"><span class="d">' + (d === todayKey ? '<i class="today-tag">Aujourd&#39;hui</i>' : '') + esc(fD.format(pd(d)).replace(/\./g, '')) + '</span>'
          + '<span class="dot"></span><span class="n">' + (n ? n + ' rendez-vous' : 'aucun rendez-vous') + '</span></button></li>';
      });
      daysEl.innerHTML = html;
      var prev = document.getElementById('prev'), next = document.getElementById('next');
      prev.disabled = page === 0; next.disabled = page >= pages - 1;
      document.getElementById('pgPrev').textContent = page > 0 ? page + '/' + pages : '';
      document.getElementById('pgNext').textContent = page < pages - 1 ? (page + 2) + '/' + pages : '';

      var day = dates[sel], list = AG.colorDay(EV.filter(function (e) { return e.d === day; }).sort(function (a, b) { return a.s - b.s; }));

      // Colonne gauche : planning de la journee, blocs colores sans texte
      var H0 = 8, H1 = 19, HH = 30;
      var timed = list.filter(function (e) { return !e.nt; }); // rendez-vous sans horaire : pas de faux creneau
      timed.forEach(function (e) { H0 = Math.min(H0, Math.floor(e.s)); H1 = Math.max(H1, Math.ceil(e.e)); });
      var lanes = [];
      timed.forEach(function (e) { for (var l = 0; l < lanes.length && lanes[l] > e.s; l++); e.lane = l; lanes[l] = e.e; });
      timed.forEach(function (e) {
        e.n = 1 + Math.max.apply(null, timed.filter(function (o) { return o.s < e.e && o.e > e.s; }).map(function (o) { return o.lane; }));
      });
      var plan = '<div class="plan" style="height:' + (H1 - H0) * HH + 'px;--ph:' + HH + 'px">', h;
      for (h = H0; h < H1; h++) plan += '<span class="ph" style="top:' + (h - H0) * HH + 'px">' + h + 'h</span>';
      plan += '<div class="pcol">';
      timed.forEach(function (e) {
        var w = 100 / e.n;
        plan += '<a class="pblk' + (AG.ended(e) ? ' ended' : '') + '" data-k="' + e.i + '"' + AG.lnk(e) + ' title="' + esc(e.t + ' - ' + (e.h || '')) + '"'
          + ' style="background:' + e.c + ';--ev-bd:' + e.c + ';top:' + ((e.s - H0) * HH + 1) + 'px;height:' + Math.max((e.e - e.s) * HH - 2, 8) + 'px;'
          + 'left:calc(' + (w * e.lane) + '% + 2px);width:calc(' + w + '% - 4px)">' + (e.dur ? '<span class="pdur">' + e.dur + '</span>' : '') + '</a>';
      });
      if (day === todayKey) {
        var t = now.getHours() + now.getMinutes() / 60;
        if (t > H0 && t < H1) plan += '<div class="pnow" style="top:' + (t - H0) * HH + 'px"></div>';
      }
      plan += '</div></div>';

      // Colonne droite : cartouches, meme couleur que le bloc
      var cards = list.length ? list.map(function (e) { return AG.card(e); }).join('') : '<p class="none">Aucun rendez-vous ce jour-l&agrave;.</p>';
      document.getElementById('tlCards').innerHTML = plan + '<div class="cards">' + cards + '</div>';
    }
    // Survol : le bloc et son cartouche s'eclairent ensemble
    var cardsEl = document.getElementById('tlCards');
    function hl(ev, on) {
      var a = ev.target.closest('[data-k]'); if (!a) return;
      cardsEl.querySelectorAll('[data-k="' + a.getAttribute('data-k') + '"]').forEach(function (x) { x.classList.toggle('hl', on); });
    }
    cardsEl.addEventListener('mouseover', function (ev) { hl(ev, true); });
    cardsEl.addEventListener('mouseout', function (ev) { hl(ev, false); });
    daysEl.addEventListener('click', function (ev) {
      var b = ev.target.closest('button'); if (!b) return;
      sel = +b.getAttribute('data-i'); render();
    });
    document.getElementById('prev').onclick = function () { page--; sel = page * per; render(); };
    document.getElementById('next').onclick = function () { page++; sel = page * per; render(); };
    window.addEventListener('resize', function () { if (perPage() !== per) { page = Math.floor(sel / perPage()); render(); } });
    AG.onChange(function () { rebuild(); render(); });
    rebuild(); render();
  })();
  </script>
  <script>
  // Calendrier mensuel : un mois a la fois, lundi-vendredi, pastille = nombre de rendez-vous affiches
  (function () {
    var ALL = (window.EVENTS || []).slice(), box = document.getElementById('months'), AG = window.AG;
    if (!box) return;
    var esc = AG.esc, fL = AG.fL;
    function key(d) { return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }
    var now = new Date(), todayKey = key(now);
    var byDay = {}, openKey = null; // rien d'ouvert a l'arrivee
    function rebuild() {
      byDay = {};
      ALL.filter(AG.shown).forEach(function (e) { (byDay[e.d] = byDay[e.d] || []).push(e); });
      Object.keys(byDay).forEach(function (k) { byDay[k].sort(function (a, b) { return AG.startH(a) - AG.startH(b); }); });
    }
    var fM = new Intl.DateTimeFormat('fr-FR', { month: 'long', year: 'numeric' });
    var HEAD = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven'];

    // Navigation : du mois courant au mois du dernier rendez-vous connu (toutes origines)
    var lastKey = ALL.map(function (e) { return e.d; }).sort().pop() || todayKey;
    var maxOff = Math.max(0, (+lastKey.slice(0, 4) - now.getFullYear()) * 12 + (+lastKey.slice(5, 7) - 1 - now.getMonth()));
    var off = 0;
    function arrow(d) { return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + d + '"/></svg>'; }
    var ARROW_L = arrow('M19 12H5M11 6l-6 6 6 6'), ARROW_R = arrow('M5 12h14M13 6l6 6-6 6');
    // openKey : 'aaaa-mm-jj' = liste d'un jour, 'aaaa-mm' = liste du mois entier (clic sur le nom du mois)
    function dayCards(k, start) { return AG.listCards((byDay[k] || []).slice(), start || 0); }
    function dayLabel(k) { var p = k.split('-'); return esc(fL.format(new Date(+p[0], p[1] - 1, +p[2]))); }
    function detailHtml(k) {
      if (k.length === 7) {
        var days = Object.keys(byDay).filter(function (x) { return x.slice(0, 7) === k; }).sort(), n = 0, c = 0;
        days.forEach(function (x) { n += byDay[x].length; });
        var p = k.split('-');
        return '<h4>' + esc(fM.format(new Date(+p[0], p[1] - 1, 1))) + ' &middot; ' + n + ' rendez-vous</h4>'
          + (days.length ? days.map(function (x) { var h = '<h5>' + dayLabel(x) + '</h5>' + dayCards(x, c); c += byDay[x].length; return h; }).join('')
                         : '<p class="none">Aucun rendez-vous ce mois-ci.</p>');
      }
      return '<h4>' + dayLabel(k) + ' &middot; ' + (byDay[k] || []).length + ' rendez-vous</h4>' + dayCards(k);
    }
    function render() {
      var html = '';
      var first = new Date(now.getFullYear(), now.getMonth() + off, 1);
      html += '<div class="month"><div class="mbar">'
        + '<button type="button" class="mnav" data-nav="-1" aria-label="Mois pr&eacute;c&eacute;dent"' + (off <= 0 ? ' disabled' : '') + '>' + ARROW_L + '</button>'
        + '<h3><button type="button" class="mtitle' + (openKey === key(first).slice(0, 7) ? ' sel' : '') + '" data-m="' + key(first).slice(0, 7) + '" title="Voir tous les rendez-vous du mois">'
        + esc(fM.format(first)) + '</button></h3>'
        + '<button type="button" class="mnav" data-nav="1" aria-label="Mois suivant"' + (off >= maxOff ? ' disabled' : '') + '>' + ARROW_R + '</button>'
        + '</div><div class="mgrid">'
        + HEAD.map(function (h) { return '<div class="mhd">' + h + '</div>'; }).join('');
      // cases vides avant le premier jour ouvre du mois
      var d = new Date(first), started = false;
      while (d.getMonth() === first.getMonth()) {
        var w = d.getDay();
        if (w > 0 && w < 6) {
          if (!started) { for (var b = 1; b < w; b++) html += '<div></div>'; started = true; }
          var k = key(d), n = (byDay[k] || []).length;
          var cls = 'mday' + (n ? ' has' : '') + (k < todayKey ? ' past' : '') + (k === todayKey ? ' today' : '') + (n && k === openKey ? ' sel' : '');
          html += '<button type="button" class="' + cls + '" data-d="' + k + '"' + (n ? '' : ' disabled')
            + ' aria-label="' + esc(fL.format(d)) + ' : ' + n + ' rendez-vous">'
            + '<span class="num">' + d.getDate() + '</span>' + (n ? '<span class="cnt">' + n + '</span>' : '') + '</button>';
        }
        d.setDate(d.getDate() + 1);
      }
      var open = openKey && (openKey.length === 7 || byDay[openKey]) && openKey.slice(0, 7) === key(first).slice(0, 7);
      html += '</div><div class="mdetail"' + (open ? '>' + detailHtml(openKey) : ' hidden>') + '</div></div>';
      box.innerHTML = html;
    }

    box.addEventListener('click', function (ev) {
      var nav = ev.target.closest('.mnav');
      if (nav) {
        // Changer de mois garde la liste du mois ouverte seulement si elle l'etait deja ; sinon tout se ferme
        off = Math.min(maxOff, Math.max(0, off + +nav.getAttribute('data-nav')));
        openKey = openKey && openKey.length === 7 ? key(new Date(now.getFullYear(), now.getMonth() + off, 1)).slice(0, 7) : null;
        render(); return;
      }
      var mt = ev.target.closest('.mtitle');
      var btn = mt || ev.target.closest('.mday.has'); if (!btn) return;
      var k = btn.getAttribute(mt ? 'data-m' : 'data-d');
      openKey = openKey === k ? null : k;
      render();
    });
    AG.onChange(function () { rebuild(); if (openKey && openKey.length > 7 && !byDay[openKey]) openKey = null; render(); });
    rebuild(); render();
  })();
  </script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>
  <script>
  // Carte : 2 modes. "actions geolocalisees" (par defaut) = une pastille par lieu avec le nombre de rendez-vous ;
  // "a distance ou non geolocalisees" (Teams, webinaire, en ligne, sans lieu) = pastilles retirees et
  // liste des rendez-vous correspondants sous la carte.
  (function () {
    var ALL = window.EVENTS || [], AG = window.AG, el = document.getElementById('map');
    var virtEl = document.getElementById('mapVirt'), det = document.getElementById('mapDetail');
    if (!el || !window.L || !AG) { var s = document.getElementById('carte'); if (s) s.hidden = true; return; }
    var esc = AG.esc;
    var map = L.map(el, { scrollWheelZoom: false, zoomSnap: 0.5 }).setView([46.6, 2.4], 5.5);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>'
    }).addTo(map);
    var layer = L.layerGroup().addTo(map), mode = 'terrain', pin = null, fitted = false;
    var MODES = [
      { k: 'terrain', t: '&eacute;v&eacute;nements g&eacute;olocalis&eacute;s' }, { k: 'distance', t: '&agrave; distance ou non g&eacute;olocalis&eacute;s' }
    ];
    // Icone : fleche de navigation type GPS
    var PC = '<svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 10.6 20.5 3.5l-7.1 17-2.3-7.6z"/></svg>';
    function sortT(a, b) { return a.d < b.d ? -1 : a.d > b.d ? 1 : AG.startH(a) - AG.startH(b); }
    function title(k) { for (var i = 0; i < MODES.length; i++) if (MODES[i].k === k) return MODES[i].t; return k; }
    // Liste sous la carte : un titre par jour, cartes vertes numerotees
    function listHtml(t, list) {
      list = list.slice().sort(sortT);
      var days = [], c = 0;
      list.forEach(function (e) { if (days.indexOf(e.d) < 0) days.push(e.d); });
      return '<h4>' + t + ' &middot; ' + list.length + ' rendez-vous</h4>'
        + days.map(function (d) {
            var day = list.filter(function (e) { return e.d === d; });
            var h = '<h5>' + esc(AG.fL.format(AG.pd(d))) + '</h5>' + AG.listCards(day, c);
            c += day.length; return h;
          }).join('');
    }
    var groups = {}, cat = {};
    function render() {
      var ev = ALL.filter(AG.shown);
      // Periode couverte par les rendez-vous affiches, ex. (6 novembre 26 - 9 decembre 26)
      var sp = document.getElementById('mapSpan'), ds = ev.map(function (e) { return e.d; }).sort();
      var fS = function (d) { var p = d.split('-'); return new Date(+p[0], p[1] - 1, +p[2]).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' }) + ' ' + p[0]; };
      if (sp) sp.innerHTML = ds.length ? '(' + fS(ds[0]) + (ds[ds.length - 1] !== ds[0] ? ' &ndash; ' + fS(ds[ds.length - 1]) : '') + ')' : '';
      groups = {}; cat = { terrain: [], distance: [] };
      ev.forEach(function (e) {
        if (e.p) {
          var k = e.p.join(',');
          (groups[k] = groups[k] || { k: k, p: e.p, l: [], list: [] }).list.push(e);
          if (groups[k].l.indexOf(e.l) < 0) groups[k].l.push(e.l);
          cat.terrain.push(e);
        } else cat.distance.push(e); // Teams, webinaire, en ligne, ou lieu non identifie
      });
      if (pin && !groups[pin]) pin = null;
      // Pastilles seulement en mode "Sur le terrain"
      layer.clearLayers();
      var pts = [];
      if (mode === 'terrain') {
        Object.keys(groups).forEach(function (k) {
          var g = groups[k], n = g.list.length;
          var icon = L.divIcon({ className: 'mpin' + (k === pin ? ' sel' : ''), html: '<span>' + n + '</span>', iconSize: [32, 32], iconAnchor: [16, 16] });
          L.marker(g.p, { icon: icon, title: g.l.join(' / ') + ' : ' + n + ' rendez-vous', keyboard: true })
            .on('click', function () { pin = pin === k ? null : k; render(); }).addTo(layer);
          pts.push(g.p);
        });
        if (pts.length && !fitted) { map.fitBounds(pts, { padding: [30, 30], maxZoom: 9 }); fitted = true; }
      }
      // Icone GPS + "evenements geolocalises" + interrupteur : allume = pastilles sur la carte,
      // eteint = pastilles retirees et liste des rendez-vous a distance ou non geolocalises
      var on = mode === 'terrain';
      virtEl.innerHTML = '<div class="pc">' + PC + '</div>'
        + '<button type="button" class="geo-sw' + (on ? ' on' : '') + '" role="switch" aria-checked="' + on + '">'
        + '<span class="lbl">&eacute;v&eacute;nements g&eacute;olocalis&eacute;s</span><span class="cnt">' + cat.terrain.length + '</span>'
        + '<span class="sw" aria-hidden="true"><span class="knob"></span></span></button>'
        + (on ? '' : '<span class="geo-off">&agrave; distance ou non g&eacute;olocalis&eacute;s : ' + cat.distance.length + '</span>');
      // Liste : le lieu clique (terrain) ou toute la categorie (a distance / inconnu)
      var html = '';
      if (mode !== 'terrain') html = cat[mode].length ? listHtml(title(mode), cat[mode]) : '<p class="none">Aucun rendez-vous.</p>';
      else if (pin) html = listHtml(esc(groups[pin].l.join(' / ')), groups[pin].list);
      det.innerHTML = html; det.hidden = !html;
    }
    virtEl.addEventListener('click', function (ev) {
      if (!ev.target.closest('.geo-sw')) return;
      mode = mode === 'terrain' ? 'distance' : 'terrain';
      pin = null; render();
    });
    AG.onChange(render);
    render();
  })();
  </script>
  <footer>Prochaine mise &agrave; jour vers $next &middot; les rendez-vous s'ouvrent sur le site d'origine.</footer>
</div>
</div>
</body>
</html>
"@

$tmp = "$outFile.tmp"
[IO.File]::WriteAllText($tmp, $page, (New-Object Text.UTF8Encoding $false))
Move-Item -Force $tmp $outFile
Log "OK : $($events.Count) rendez-vous"
