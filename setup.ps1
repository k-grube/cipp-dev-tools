#Requires -Version 7
param([switch]$SkipGraph)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Assert-Tool($name, $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "missing prerequisite: $name -> $hint"
    }
}

Assert-Tool git 'https://git-scm.com'
Assert-Tool gh 'https://cli.github.com then: gh auth login'
Assert-Tool docker 'Docker Desktop: https://docker.com'
Assert-Tool wt 'Windows Terminal (upstream dev launcher requires it)'
Assert-Tool node 'https://nodejs.org'
Assert-Tool yarn 'npm install -g yarn'
Assert-Tool python 'https://python.org'

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'gh not authenticated -> gh auth login'
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'docker desktop not running'
}

$cipp = Join-Path $root 'cipp'
if ((Test-Path $cipp) -and -not (Test-Path (Join-Path $cipp '.git'))) {
    throw "cipp\ exists but is not a git clone (interrupted setup?) -> delete $cipp and re-run"
}
if (-not (Test-Path $cipp)) {
    # forks CyberDrain/CIPP under the authed user (reuses an existing fork), clones into cipp\
    Push-Location $root
    try {
        gh repo fork CyberDrain/CIPP --clone -- cipp
        if ($LASTEXITCODE -ne 0) {
            throw 'gh repo fork --clone failed'
        }
    } finally {
        Pop-Location
    }
}

# idempotent remote repair: origin = fork (left as gh set it), upstream = CyberDrain
Push-Location $cipp
try {
    if ((git remote) -notcontains 'upstream') {
        git remote add upstream https://github.com/CyberDrain/CIPP.git
    }
    git remote set-url upstream https://github.com/CyberDrain/CIPP.git
    if ($LASTEXITCODE -ne 0) {
        throw 'failed to configure upstream remote in cipp\'
    }
} finally {
    Pop-Location
}

python -c "import graphify" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install graphifyy==0.9.12
    if ($LASTEXITCODE -ne 0) {
        throw 'pip install graphifyy==0.9.12 failed'
    }
}
python -c "import importlib.metadata as m; v = m.version('graphifyy'); assert v == '0.9.12', v; print('graphifyy', v)"
if ($LASTEXITCODE -ne 0) {
    throw 'graphifyy version check failed, expected exactly 0.9.12'
}

if (-not $SkipGraph) {
    $rebuild = Join-Path $root 'graph-tools\rebuild-graph.ps1'
    if (Test-Path $rebuild) {
        & $rebuild
    } else {
        Write-Host 'graph-tools not present yet, skipping graph build'
    }
}
Write-Host 'setup complete'
