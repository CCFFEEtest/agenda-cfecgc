# Publie les modifications de ce dossier sur GitHub (depot CCFFEEtest/agenda-cfecgc).
# Le site est ensuite redeploye automatiquement par GitHub Actions.
# Usage : .\publier.ps1 ["message"]   ou double-clic sur publier.cmd
param([string]$Message = "Mise a jour de l'agenda")

Set-Location $PSScriptRoot
$repo = 'https://github.com/CCFFEEtest/agenda-cfecgc.git'

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) {
    $p = 'C:\Program Files\Git\cmd\git.exe'
    if (Test-Path $p) { $git = $p }
    else { Write-Host "Git n'est pas installe. Lance : winget install --id Git.Git -e"; exit 1 }
}

function G { & $git @args; if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR : git $args"; exit 1 } }

# Premiere fois : relie le dossier au depot existant sans toucher aux fichiers locaux.
if (-not (Test-Path .git)) {
    G init -q
    G remote add origin $repo
    G config user.name 'CCFFEEtest'
    G config user.email 'CCFFEEtest@users.noreply.github.com'
    G fetch -q origin main
    G checkout -q -B main
    G reset -q origin/main
    G branch -q -u origin/main
}

G add -A
if (& $git status --porcelain) {
    & $git status --short
    G commit -q -m $Message
}
G pull -q --rebase origin main
if (-not (& $git log --oneline origin/main..main)) {
    Write-Host 'Rien a publier : GitHub est deja a jour.'
    exit 0
}
G push -q origin main
Write-Host 'Publie. Le site sera a jour dans 2 a 3 minutes : https://ccffeetest.github.io/agenda-cfecgc/'
