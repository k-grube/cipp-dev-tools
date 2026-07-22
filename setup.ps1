#Requires -Version 7.2
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

python --version *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'python on PATH is not a working interpreter (windows store stub?) -> install from https://python.org and disable the app execution alias'
}

# graphifyy needs python >=3.10
python -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"
if ($LASTEXITCODE -ne 0) {
    $pyVer = python -c "import platform; print(platform.python_version())"
    throw "python is $pyVer, graphifyy needs >=3.10 -> upgrade from https://python.org"
}

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
    $login = gh api user -q .login
    if ($LASTEXITCODE -ne 0 -or -not $login) {
        throw 'could not determine the logged-in github user (gh api user failed)'
    }
    # does <login>/CIPP already exist, and is it a fork of upstream?
    $parent = gh api "repos/$login/CIPP" -q '.parent.full_name // ""' 2>$null
    $defaultOk = $true
    if ($LASTEXITCODE -eq 0 -and $parent -eq 'CyberDrain/CIPP') {
        $prompt = "found your existing fork $login/CIPP. enter = clone it, n = abort, or owner/repo to use a different fork"
    } elseif ($LASTEXITCODE -eq 0) {
        $prompt = "$login/CIPP exists on github but is not a fork of CyberDrain/CIPP. n = abort, or owner/repo of a fork to use instead"
        $defaultOk = $false
    } else {
        $prompt = "will fork CyberDrain/CIPP to $login/CIPP and clone into cipp\. enter = ok, n = abort, or owner/repo to fork/clone elsewhere (e.g. my-org/CIPP)"
    }
    $answer = (Read-Host $prompt).Trim() -replace '\\', '/'
    Push-Location $root
    try {
        if ($answer -match '/') {
            if ($answer -notmatch '^[\w.-]+/[\w.-]+$') {
                throw "unrecognized fork name '$answer' (expected owner/repo)"
            }
            $forkParent = gh api "repos/$answer" -q '.parent.full_name // ""' 2>$null
            if ($LASTEXITCODE -eq 0) {
                if ($forkParent -ne 'CyberDrain/CIPP') {
                    Write-Warning "$answer is not marked as a fork of CyberDrain/CIPP on github, PRs from it may not work"
                }
                git clone "https://github.com/$answer.git" cipp
                if ($LASTEXITCODE -ne 0) {
                    throw "git clone of $answer failed"
                }
            } else {
                $owner, $repo = $answer -split '/'
                if ($repo -ne 'CIPP') {
                    throw "$answer not found on github (gh can only create the fork named CIPP) -> create it first or use <owner>/CIPP"
                }
                gh repo fork CyberDrain/CIPP --org $owner --clone -- cipp
                if ($LASTEXITCODE -ne 0) {
                    throw "gh repo fork --org $owner failed"
                }
            }
        } elseif ($answer -match '^[nN]') {
            throw 'stopped before forking -> re-run setup.ps1 when ready'
        } elseif ($answer -eq '' -or $answer -match '^[yY]([eE][sS])?$') {
            if (-not $defaultOk) {
                throw "$login/CIPP is not a fork of CyberDrain/CIPP -> re-run and enter an owner/repo fork to use instead"
            }
            gh repo fork CyberDrain/CIPP --clone -- cipp
            if ($LASTEXITCODE -ne 0) {
                throw 'gh repo fork --clone failed'
            }
        } else {
            throw "unrecognized answer '$answer' (expected enter, n, or owner/repo)"
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

    $originUrl = git remote get-url origin
    if ($originUrl -match 'github\.com[:/]CyberDrain/CIPP') {
        Write-Warning "origin points at upstream ($originUrl), not a fork -> PRs from this clone won't work; fork CyberDrain/CIPP and update origin"
    }
} finally {
    Pop-Location
}

python -c "import graphify" 2>$null
if ($LASTEXITCODE -ne 0) {
    python -m pip install graphifyy==0.9.12
    if ($LASTEXITCODE -ne 0) {
        throw 'python -m pip install graphifyy==0.9.12 failed'
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
        if ($LASTEXITCODE -ne 0) {
            throw 'graph build failed -> fix the error above, then re-run setup.ps1 or run graph-tools\rebuild-graph.ps1 directly'
        }
    } else {
        Write-Host 'graph-tools not present yet, skipping graph build'
    }
}
Write-Host 'setup complete'
