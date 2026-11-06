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

# ---------- Generation de la page ----------
# Donnees de la timeline (rendu en JavaScript dans la page)
$evData = @($events | ForEach-Object {
  $o = [ordered]@{ t = $_.Title; u = $_.Url; d = $_.Date.ToString('yyyy-MM-dd'); h = $_.Time; g = $_.Tag; x = $_.Extract }
  if ($_.Added) { $o.a = 1 }
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
    <div class="hrow"><h2>Vue calendrier</h2><div class="filters" role="group" aria-label="Afficher selon l&#39;origine"><button type="button" class="flt" data-f="nat" aria-pressed="true">&eacute;v&eacute;nements du calendrier national</button><button type="button" class="flt flt-mail" data-f="mail" aria-pressed="true">communications email</button></div></div>
    <div class="months" id="months"></div>
  </section>
  <script>window.EVENTS = $evJson;</script>
"@
$now   = ParisNow
$stamp = $now.ToString("dddd d MMMM yyyy '&agrave;' HH'h'mm", $fr)
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
<link rel="stylesheet" href="style.css">
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
<div class="banner"><h1><a href="./">Agenda CFE-CGC Orange FC</a></h1><button type="button" class="bn-ico" id="themeBtn" title="Changer de th&egrave;me" aria-label="Changer de th&egrave;me"><svg class="ico-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4.5"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg><svg class="ico-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z"/></svg></button></div>
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
    <div class="hrow"><h2>Prochains &eacute;v&eacute;nements</h2><div class="filters" role="group" aria-label="Afficher selon l&#39;origine"><button type="button" class="flt" data-f="nat" aria-pressed="true">&eacute;v&eacute;nements du calendrier national</button><button type="button" class="flt flt-mail" data-f="mail" aria-pressed="true">communications email</button></div></div>
    <p class="sub">$($events.Count - $added) rendez-vous &agrave; venir sur <a href="$source" target="_blank" rel="noopener">cfecgc-orange.org</a>$(if ($added) { " + $added issu$(if ($added -gt 1) { 's' }) de communications email" }) &middot; mis &agrave; jour $stamp</p>
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
    function srcTag(e) { return '<span class="src' + (e.a ? ' src-mail' : '') + '">' + (e.a ? 'communication email' : '&eacute;v&eacute;nement du calendrier national') + '</span>'; }
    // Cartouche d'un rendez-vous (timeline et liste du jour du calendrier)
    // Page d'abonnement aux communications (bouton "S'abonner" du site cfecgc-orange.org)
    var SUBSCRIBE = 'https://odyssee.cfecgc-orange.org/com/page/1387';
    function card(e) {
      // Communication email : la carte n'est pas un lien (un lien ne peut pas en contenir un autre)
      var tag = e.a || !e.u ? 'div' : 'a';
      return '<' + tag + ' class="ev-card' + (tag === 'div' ? ' nolink' : '') + '" data-k="' + e.i + '" style="--ev-bd:' + e.c + '"' + (tag === 'a' ? lnk(e) : '') + '>'
        + '<span class="when"><b>' + esc(fL.format(pd(e.d))) + '</b>' + '<span>' + (e.h ? esc(e.h) : 'Horaire non pr&eacute;cis&eacute;') + '</span>'
        + (e.g && !isNat(e.g) ? '<span>' + esc(e.g) + '</span>' : '') + srcTag(e) + '</span>'
        + '<span class="ttl">' + esc(e.t) + '</span>'
        + (e.x ? '<p>' + esc(e.x) + '</p>' : '')
        + (e.a ? '<span class="more">&rarr; voir mail (<a href="' + SUBSCRIBE + '" target="_blank" rel="noopener">inscrivez-vous aux communications</a>)</span>'
               : e.u ? '<span class="more">Voir le d&eacute;tail &rarr;</span>' : '') + '</' + tag + '>';
    }
    function startH(e) { var m = /(\d{1,2})\s*h\s*(\d{2})?/i.exec(e.h || ''); return m ? +m[1] * 60 + (+(m[2] || 0)) : 0; }
    // Couleur par ordre de debut dans la journee (meme regle partout)
    function colorDay(list) { list.forEach(function (e, i) { e.c = COLORS[i % COLORS.length]; e.i = i; }); return list; }

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
    return { esc: esc, pd: pd, lnk: lnk, card: card, startH: startH, colorDay: colorDay, shown: shown, fL: fL,
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
      e.dur = '';
      if (e.s != null && e.e != null && e.e > e.s) {
        var mn = Math.round((e.e - e.s) * 60), hh = Math.floor(mn / 60), mm = mn % 60;
        e.dur = hh ? hh + 'h' + (mm ? (mm < 10 ? '0' : '') + mm : '') : mm + 'min';
      }
      if (e.s == null) { e.s = 9; e.e = 10; } if (e.e == null || e.e <= e.s) e.e = e.s + 1;
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
      list.forEach(function (e) { H0 = Math.min(H0, Math.floor(e.s)); H1 = Math.max(H1, Math.ceil(e.e)); });
      var lanes = [];
      list.forEach(function (e) { for (var l = 0; l < lanes.length && lanes[l] > e.s; l++); e.lane = l; lanes[l] = e.e; });
      list.forEach(function (e) {
        e.n = 1 + Math.max.apply(null, list.filter(function (o) { return o.s < e.e && o.e > e.s; }).map(function (o) { return o.lane; }));
      });
      var plan = '<div class="plan" style="height:' + (H1 - H0) * HH + 'px;--ph:' + HH + 'px">', h;
      for (h = H0; h < H1; h++) plan += '<span class="ph" style="top:' + (h - H0) * HH + 'px">' + h + 'h</span>';
      plan += '<div class="pcol">';
      list.forEach(function (e) {
        var w = 100 / e.n;
        plan += '<a class="pblk" data-k="' + e.i + '"' + AG.lnk(e) + ' title="' + esc(e.t + ' - ' + (e.h || '')) + '"'
          + ' style="background:' + e.c + ';--ev-bd:' + e.c + ';top:' + ((e.s - H0) * HH + 1) + 'px;height:' + Math.max((e.e - e.s) * HH - 2, 8) + 'px;'
          + 'left:calc(' + (w * e.lane) + '% + 2px);width:calc(' + w + '% - 4px)">' + (e.dur ? '<span class="pdur">' + e.dur + '</span>' : '') + '</a>';
      });
      if (day === todayKey) {
        var t = now.getHours() + now.getMinutes() / 60;
        if (t > H0 && t < H1) plan += '<div class="pnow" style="top:' + (t - H0) * HH + 'px"></div>';
      }
      plan += '</div></div>';

      // Colonne droite : cartouches, meme couleur que le bloc
      var cards = list.length ? list.map(AG.card).join('') : '<p class="none">Aucun rendez-vous ce jour-l&agrave;.</p>';
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
    var byDay = {}, openKey = todayKey.slice(0, 7); // liste du mois en cours ouverte des l'arrivee
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
    function dayCards(k) { return '<div class="cards">' + AG.colorDay((byDay[k] || []).slice()).map(AG.card).join('') + '</div>'; }
    function dayLabel(k) { var p = k.split('-'); return esc(fL.format(new Date(+p[0], p[1] - 1, +p[2]))); }
    function detailHtml(k) {
      if (k.length === 7) {
        var days = Object.keys(byDay).filter(function (x) { return x.slice(0, 7) === k; }).sort(), n = 0;
        days.forEach(function (x) { n += byDay[x].length; });
        var p = k.split('-');
        return '<h4>' + esc(fM.format(new Date(+p[0], p[1] - 1, 1))) + ' &middot; ' + n + ' rendez-vous</h4>'
          + (days.length ? days.map(function (x) { return '<h5>' + dayLabel(x) + '</h5>' + dayCards(x); }).join('')
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
        // Changer de mois ouvre directement la liste du mois entier
        off = Math.min(maxOff, Math.max(0, off + +nav.getAttribute('data-nav')));
        openKey = key(new Date(now.getFullYear(), now.getMonth() + off, 1)).slice(0, 7);
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
