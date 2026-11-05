# Petit serveur local pour index.html (http://localhost:8080)
$root = $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/")
$listener.Start()
Write-Host "Serveur sur http://localhost:8080"
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
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $res.StatusCode = 404
  }
  $res.Close()
}
