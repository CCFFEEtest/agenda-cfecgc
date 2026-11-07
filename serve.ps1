# Petit serveur local pour index.html (http://localhost:8080)
# -Port (ou variable PORT) : autre port si 8080 est deja pris (ex. par une autre session)
param([int]$Port = $(if ($env:PORT) { [int]$env:PORT } else { 8080 }))
$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serveur sur http://localhost:$Port"
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.LocalPath.TrimStart('/')
  if ($path -eq '') { $path = 'index.html' }
  $file = Join-Path $root $path
  $res = $ctx.Response
  if ((Test-Path $file -PathType Leaf) -and ($file -like "$root*")) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($file -like '*.html') { $res.ContentType = 'text/html; charset=utf-8' }
    if ($file -like '*.png') { $res.ContentType = 'image/png' }
    if ($file -like '*.webp') { $res.ContentType = 'image/webp' }
    if ($file -like '*.svg') { $res.ContentType = 'image/svg+xml' }
    if ($file -like '*.css') { $res.ContentType = 'text/css; charset=utf-8' }
    if ($file -like '*.js') { $res.ContentType = 'text/javascript; charset=utf-8' }
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $res.StatusCode = 404
  }
  $res.Close()
}
