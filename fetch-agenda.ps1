# Recupere les rendez-vous a venir de l'agenda de cfecgc-orange.org
# et genere index.html (timeline + planning du jour + cartouches).
# A lancer toutes les 2 heures (Planificateur de taches Windows).

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

# ---------- Generation de la page ----------
# Donnees de la timeline (rendu en JavaScript dans la page)
$evData = @($events | ForEach-Object {
  [ordered]@{ t = $_.Title; u = $_.Url; d = $_.Date.ToString('yyyy-MM-dd'); h = $_.Time; g = $_.Tag; x = $_.Extract }
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
  <section class="recap">
    <h2>Calendrier des &eacute;v&eacute;nements</h2>
    <div class="months" id="months"></div>
  </section>
  <script>window.EVENTS = $evJson;</script>
"@
$now   = ParisNow
$stamp = $now.ToString("dddd d MMMM yyyy '&agrave;' HH'h'mm", $fr)
$next  = $now.AddHours(2).ToString("HH'h'mm", $fr)

$page = @"
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="900">
<title>Agenda CFE-CGC Orange</title>
<style>
  :root {
    --bg: #f6f6f8; --card: #ffffff; --text: #16161d; --muted: #6b6b7a;
    --line: #e7e7ee; --accent: #ff7900; --accent-soft: #fff1e5;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #111116; --card: #1b1b22; --text: #f2f2f6; --muted: #9a9aab;
            --line: #2a2a34; --accent: #ff8a1f; --accent-soft: #2b1d10; }
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: "Segoe UI", system-ui, -apple-system, sans-serif; background: var(--bg);
         color: var(--text); line-height: 1.4; padding: 40px 16px 64px; }
  .wrap { max-width: 1040px; margin: 0 auto; }
  header { margin-bottom: 28px; }
  .kicker { display: inline-block; font-size: .75rem; font-weight: 700; letter-spacing: .12em;
            text-transform: uppercase; color: var(--accent); background: var(--accent-soft);
            padding: 4px 10px; border-radius: 99px; }
  h1 { font-size: clamp(1.7rem, 5vw, 2.4rem); letter-spacing: -.02em; margin: 12px 0 6px; }
  .sub { color: var(--muted); font-size: .95rem; }
  .sub a { color: inherit; }
  a:focus-visible, button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  .tl-card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; }
  .tl { display: flex; align-items: stretch; border-bottom: 1px solid var(--line); }
  .tl-arrow { flex: none; width: 84px; font: inherit; background: none; border: 0; cursor: pointer; color: #22222b;
              display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 5px; padding: 14px 0; }
  .tl-arrow:disabled { color: #c9c9d2; cursor: default; }
  .tl-arrow .pg { font-size: .8rem; font-weight: 700; min-height: 1em; }
  .tl-arrow .ar { display: grid; place-items: center; width: 44px; height: 44px; border-radius: 99px;
                  border: 2px solid currentColor; background: #fff; transition: transform .15s, box-shadow .15s; }
  .tl-arrow .ar svg { width: 22px; height: 22px; }
  .tl-arrow:disabled .ar { border-color: var(--line); }
  .tl-arrow:hover:not(:disabled) .ar { transform: scale(1.06); box-shadow: 0 3px 10px rgba(0,0,0,.15); }
  .tl-arrow .lb { font-size: .75rem; color: var(--muted); }
  .tl-days { list-style: none; flex: 1; display: grid; grid-template-columns: repeat(var(--n, 5), 1fr); position: relative; }
  .tl-days::before { content: ""; position: absolute; left: 0; right: 0; top: 50%; height: 2px; background: var(--line); }
  .tl-days li { position: relative; }
  .tl-days button { width: 100%; height: 100%; font: inherit; background: none; border: 0; cursor: pointer; color: var(--text);
                    display: grid; grid-template-rows: 1fr 16px 1fr; align-items: center; justify-items: center; padding: 12px 4px; }
  .tl-days .d { font-weight: 700; font-size: .85rem; text-transform: uppercase; letter-spacing: .04em; align-self: end; padding-bottom: 8px; }
  .tl-days .dot { width: 12px; height: 12px; border-radius: 50%; background: var(--accent); position: relative; z-index: 1; }
  .tl-days .n { font-size: .78rem; color: var(--muted); align-self: start; padding-top: 8px; }
  .tl-days button:hover .dot { transform: scale(1.25); }
  .tl-days .sel button { background: var(--accent); color: #fff; }
  .tl-days .sel .dot { background: #fff; }
  .tl-days .sel .n { color: #fff; }
  .today-tag { display: block; font-style: normal; font-size: .62rem; letter-spacing: .1em; margin-bottom: 3px;
               color: #fff; background: var(--text); border-radius: 99px; padding: 2px 8px; width: max-content; margin-inline: auto; }
  .tl-days .is-today:not(.sel) button { background: var(--accent-soft); box-shadow: inset 0 -3px 0 var(--accent); }
  .tl-days .is-today .dot { box-shadow: 0 0 0 4px rgba(255,121,0,.25); }
  .tl-days .sel .today-tag { background: #fff; color: var(--accent); }
  .tl-cards { display: grid; grid-template-columns: 170px 1fr; gap: 16px; padding: 16px; align-items: start; }
  .plan { position: sticky; top: 12px; margin-left: 30px; border-left: 1px solid var(--line);
          background-image: linear-gradient(var(--line) 1px, transparent 1px); background-size: 100% var(--ph); }
  .ph { position: absolute; left: -32px; transform: translateY(-50%); font-size: .68rem; color: var(--muted); }
  .ph:first-child { transform: none; }
  .pcol { position: absolute; inset: 0; }
  .pblk { position: absolute; border-radius: 5px; opacity: .85; transition: opacity .15s, box-shadow .15s; }
  .pblk.hl, .pblk:hover { opacity: 1; box-shadow: 0 0 0 2px var(--card), 0 0 0 4px currentColor; color: var(--text); }
  .pnow { position: absolute; left: -4px; right: 0; height: 2px; background: #d9534f; }
  .cards { display: grid; gap: 10px; }
  .none { color: var(--muted); font-size: .9rem; padding: 8px 0; }
  .ev-card { display: flex; flex-direction: column; gap: 8px; padding: 14px 16px; border: 1px solid var(--line);
             border-left: 5px solid var(--ev-bd); border-radius: 10px; background: var(--card);
             color: var(--text); text-decoration: none; transition: box-shadow .15s, transform .15s; }
  .ev-card:hover, .ev-card.hl { box-shadow: 0 4px 14px rgba(0,0,0,.10); transform: translateX(2px); }
  .ev-card .when { display: flex; flex-wrap: wrap; gap: 6px 10px; font-size: .78rem; color: var(--muted); }
  .ev-card .when b { color: var(--text); }
  .ev-card .ttl { font-weight: 600; line-height: 1.3; }
  .ev-card p { font-size: .85rem; color: var(--muted); display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
  .ev-card .more { font-size: .8rem; color: var(--accent); font-weight: 600; margin-top: auto; }
  @media (max-width: 600px) {
    .tl-arrow { width: 52px; } .tl-arrow .lb { display: none; }
    .tl-arrow .ar { width: 38px; height: 38px; } .tl-arrow .ar svg { width: 19px; height: 19px; }
    .tl-days .d { font-size: .72rem; }
    .tl-cards { grid-template-columns: 96px 1fr; gap: 10px; padding: 12px; }
  }
  .recap { margin-top: 32px; }
  .recap h2 { font-size: 1.15rem; margin-bottom: 12px; }
  .months { display: grid; gap: 20px; }
  .month { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
  .mbar { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
  .month h3 { font-size: 1.05rem; text-transform: capitalize; text-align: center; flex: 1; }
  .mnav { display: grid; place-items: center; width: 44px; height: 44px; border-radius: 99px; cursor: pointer; padding: 0;
          border: 2px solid #22222b; background: #fff; color: #22222b; transition: transform .15s, box-shadow .15s; }
  .mnav svg { width: 22px; height: 22px; }
  .mnav:hover:not(:disabled) { transform: scale(1.06); box-shadow: 0 3px 10px rgba(0,0,0,.15); }
  .mnav:disabled { border-color: var(--line); color: #c9c9d2; cursor: default; }
  .mgrid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 6px; }
  .mhd { font-size: .72rem; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; padding: 0 4px 4px; }
  .mday { position: relative; height: 64px; font: inherit; text-align: left; padding: 6px 8px; border-radius: 10px;
          border: 1px solid var(--line); background: var(--card); color: var(--text); }
  .mday .num { font-weight: 600; font-size: .95rem; }
  .mday .cnt { position: absolute; right: 7px; bottom: 7px; min-width: 22px; height: 22px; padding: 0 6px; border-radius: 99px;
               background: var(--accent); color: #fff; font-size: .75rem; font-weight: 700; line-height: 22px; text-align: center; }
  .mday.has { cursor: pointer; }
  .mday.has:hover { border-color: var(--accent); }
  .mday:disabled { cursor: default; color: var(--muted); }
  .mday.past { opacity: .45; }
  .mday.today { border: 2px solid #22222b; }
  .mday.today .num { color: var(--accent); }
  .mday.today .num::after { content: " auj."; font-size: .7rem; font-weight: 600; }
  .mday.sel { background: var(--accent-soft); border-color: var(--accent); }
  .mdetail { margin-top: 14px; border-top: 1px solid var(--line); padding-top: 12px; }
  .mdetail h4 { font-size: .9rem; margin-bottom: 8px; }
  .mdetail h4::first-letter { text-transform: uppercase; }
  .mdetail ul { list-style: none; display: grid; gap: 6px; }
  .mdetail a { display: grid; grid-template-columns: 110px 1fr; gap: 12px; align-items: baseline; padding: 10px 12px;
               border: 1px solid var(--line); border-radius: 10px; color: var(--text); text-decoration: none; }
  .mdetail a:hover { border-color: var(--accent); background: var(--accent-soft); }
  .mdetail .mh { font-size: .8rem; color: var(--muted); }
  .mdetail .mt { font-weight: 600; line-height: 1.3; }
  .mdetail .mt small { display: block; font-weight: 400; color: var(--muted); font-size: .75rem; margin-top: 2px; }
  @media (max-width: 600px) {
    .month { padding: 12px; } .mgrid { gap: 4px; }
    .mday { height: 52px; padding: 4px 6px; } .mday .cnt { right: 4px; bottom: 4px; min-width: 18px; height: 18px; line-height: 18px; font-size: .68rem; padding: 0 4px; }
    .mday.today .num::after { content: ""; }
    .mdetail a { grid-template-columns: 1fr; gap: 2px; }
  }
  footer { margin-top: 28px; font-size: .8rem; color: var(--muted); text-align: center; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <span class="kicker">Agenda</span>
    <h1>Prochains &eacute;v&eacute;nements</h1>
    <p class="sub">$($events.Count) rendez-vous &agrave; venir sur <a href="$source" target="_blank" rel="noopener">cfecgc-orange.org</a> &middot; mis &agrave; jour $stamp</p>
  </header>
$eventsHtml
  <script>
  (function () {
    var EV = window.EVENTS || [], daysEl = document.getElementById('tlDays');
    if (!daysEl || !EV.length) return;
    function esc(s) { var d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
    function pd(s) { var p = s.split('-'); return new Date(+p[0], p[1] - 1, +p[2]); }
    var now = new Date(), todayKey = now.getFullYear() + '-' + ('0' + (now.getMonth() + 1)).slice(-2) + '-' + ('0' + now.getDate()).slice(-2);
    // Une date par point de la timeline, sans samedi ni dimanche
    var dates = [];
    EV.forEach(function (e) { var w = pd(e.d).getDay(); if (w > 0 && w < 6 && dates.indexOf(e.d) < 0) dates.push(e.d); });
    if (now.getDay() > 0 && now.getDay() < 6 && dates.indexOf(todayKey) < 0) dates.push(todayKey); // aujourd'hui toujours present
    function hm(s) { var m = /(\d{1,2})\s*h\s*(\d{2})?/i.exec(s || ''); return m ? +m[1] + (+(m[2] || 0)) / 60 : null; }
    EV.forEach(function (e) {
      var p = (e.h || '').split('-'); e.s = hm(p[0]); e.e = hm(p[1]);
      if (e.s == null) { e.s = 9; e.e = 10; } if (e.e == null || e.e <= e.s) e.e = e.s + 1;
    });
    var COLORS = ['#5f9e6e', '#5b86c5', '#e69a4c', '#9aa0a8', '#e08a8a', '#9580c4', '#4fa9a6', '#c7a64a'];
    dates.sort();
    if (!dates.length) return;
    var fD = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
    var fL = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    var sel = 0, page = 0, per = 5;
    for (var i = 0; i < dates.length; i++) { if (dates[i] >= todayKey) { sel = i; break; } }

    function perPage() { return window.innerWidth < 600 ? 3 : 5; }
    function render() {
      per = perPage();
      var pages = Math.ceil(dates.length / per);
      if (page > pages - 1) page = pages - 1;
      var from = page * per, slice = dates.slice(from, from + per), html = '';
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

      var day = dates[sel], list = EV.filter(function (e) { return e.d === day; }).sort(function (a, b) { return a.s - b.s; });
      list.forEach(function (e, i) { e.c = COLORS[i % COLORS.length]; e.i = i; });

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
        plan += '<a class="pblk" data-k="' + e.i + '" href="' + esc(e.u) + '" target="_blank" rel="noopener" title="' + esc(e.t + ' - ' + (e.h || '')) + '"'
          + ' style="background:' + e.c + ';top:' + ((e.s - H0) * HH + 1) + 'px;height:' + Math.max((e.e - e.s) * HH - 2, 8) + 'px;'
          + 'left:calc(' + (w * e.lane) + '% + 2px);width:calc(' + w + '% - 4px)"></a>';
      });
      if (day === todayKey) {
        var t = now.getHours() + now.getMinutes() / 60;
        if (t > H0 && t < H1) plan += '<div class="pnow" style="top:' + (t - H0) * HH + 'px"></div>';
      }
      plan += '</div></div>';

      // Colonne droite : cartouches, meme couleur que le bloc
      var cards = list.length ? list.map(function (e) {
        return '<a class="ev-card" data-k="' + e.i + '" style="--ev-bd:' + e.c + '" href="' + esc(e.u) + '" target="_blank" rel="noopener">'
          + '<span class="when"><b>' + esc(fL.format(pd(e.d))) + '</b>' + (e.h ? '<span>' + esc(e.h) + '</span>' : '')
          + (e.g ? '<span>' + esc(e.g) + '</span>' : '') + '</span>'
          + '<span class="ttl">' + esc(e.t) + '</span>'
          + (e.x ? '<p>' + esc(e.x) + '</p>' : '')
          + '<span class="more">Voir le d&eacute;tail &rarr;</span></a>';
      }).join('') : '<p class="none">Aucun rendez-vous ce jour-l&agrave;.</p>';
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
    page = Math.floor(sel / perPage());
    window.addEventListener('resize', function () { if (perPage() !== per) { page = Math.floor(sel / perPage()); render(); } });
    render();
  })();
  </script>
  <script>
  // Calendrier mensuel : mois en cours + mois suivant, lundi-vendredi, pastille = nombre de rendez-vous
  (function () {
    var EV = (window.EVENTS || []).slice(), box = document.getElementById('months');
    if (!box) return;
    function esc(s) { var d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }
    function key(d) { return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }
    function startH(e) { var m = /(\d{1,2})\s*h\s*(\d{2})?/i.exec(e.h || ''); return m ? +m[1] * 60 + (+(m[2] || 0)) : 0; }
    var now = new Date(), todayKey = key(now);
    var byDay = {};
    EV.forEach(function (e) { (byDay[e.d] = byDay[e.d] || []).push(e); });
    Object.keys(byDay).forEach(function (k) { byDay[k].sort(function (a, b) { return startH(a) - startH(b); }); });
    var fM = new Intl.DateTimeFormat('fr-FR', { month: 'long', year: 'numeric' });
    var fL = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    var HEAD = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven'];

    // Un seul mois affiche : le mois courant, puis les suivants tant qu'il reste des rendez-vous
    var lastKey = Object.keys(byDay).sort().pop() || todayKey;
    var maxOff = Math.max(0, (+lastKey.slice(0, 4) - now.getFullYear()) * 12 + (+lastKey.slice(5, 7) - 1 - now.getMonth()));
    var off = 0;
    function arrow(d) { return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="' + d + '"/></svg>'; }
    var ARROW_L = arrow('M19 12H5M11 6l-6 6 6 6'), ARROW_R = arrow('M5 12h14M13 6l6 6-6 6');
    function render() {
      var html = '';
      var first = new Date(now.getFullYear(), now.getMonth() + off, 1);
      html += '<div class="month"><div class="mbar">'
        + '<button type="button" class="mnav" data-nav="-1" aria-label="Mois pr&eacute;c&eacute;dent"' + (off <= 0 ? ' disabled' : '') + '>' + ARROW_L + '</button>'
        + '<h3>' + esc(fM.format(first)) + '</h3>'
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
          var cls = 'mday' + (n ? ' has' : '') + (k < todayKey ? ' past' : '') + (k === todayKey ? ' today' : '');
          html += '<button type="button" class="' + cls + '" data-d="' + k + '"' + (n ? '' : ' disabled')
            + ' aria-label="' + esc(fL.format(d)) + ' : ' + n + ' rendez-vous">'
            + '<span class="num">' + d.getDate() + '</span>' + (n ? '<span class="cnt">' + n + '</span>' : '') + '</button>';
        }
        d.setDate(d.getDate() + 1);
      }
      html += '</div><div class="mdetail" hidden></div></div>';
      box.innerHTML = html;
    }
    render();

    box.addEventListener('click', function (ev) {
      var nav = ev.target.closest('.mnav');
      if (nav) { off = Math.min(maxOff, Math.max(0, off + +nav.getAttribute('data-nav'))); render(); return; }
      var btn = ev.target.closest('.mday.has'); if (!btn) return;
      var month = btn.closest('.month'), detail = month.querySelector('.mdetail'), k = btn.getAttribute('data-d');
      var wasSel = btn.classList.contains('sel');
      month.querySelectorAll('.mday.sel').forEach(function (x) { x.classList.remove('sel'); });
      if (wasSel) { detail.hidden = true; detail.innerHTML = ''; return; }
      btn.classList.add('sel');
      var p = k.split('-'), list = byDay[k];
      detail.innerHTML = '<h4>' + esc(fL.format(new Date(+p[0], p[1] - 1, +p[2]))) + ' &middot; ' + list.length + ' rendez-vous</h4><ul>'
        + list.map(function (e) {
            return '<li><a href="' + esc(e.u) + '" target="_blank" rel="noopener"><span class="mh">' + (e.h ? esc(e.h) : 'Horaire non pr&eacute;cis&eacute;') + '</span>'
              + '<span class="mt">' + esc(e.t) + (e.g ? '<small>' + esc(e.g) + '</small>' : '') + '</span></a></li>';
          }).join('') + '</ul>';
      detail.hidden = false;
    });
  })();
  </script>
  <footer>Prochaine mise &agrave; jour vers $next &middot; les rendez-vous s'ouvrent sur le site d'origine.</footer>
</div>
</body>
</html>
"@

$tmp = "$outFile.tmp"
[IO.File]::WriteAllText($tmp, $page, (New-Object Text.UTF8Encoding $false))
Move-Item -Force $tmp $outFile
Log "OK : $($events.Count) rendez-vous"
