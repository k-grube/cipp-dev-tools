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

# non-elevated git refuses admin-owned repos (dubious ownership), elevated shells mask the
# error so add unconditionally, dedupe keeps re-runs clean
function Add-SafeDirectory([string]$path) {
    $p = $path -replace '\\', '/'
    if ((git config --global --get-all safe.directory) -notcontains $p) {
        git config --global --add safe.directory $p
    }
}
Add-SafeDirectory $root

# fork-prompt + clone + remote repair, shared by cipp and craft
function Initialize-ForkClone {
    param([string]$Upstream, [string]$Dest)
    $repoName = ($Upstream -split '/')[1]
    $destPath = Join-Path $root $Dest
    if ((Test-Path $destPath) -and -not (Test-Path (Join-Path $destPath '.git'))) {
        throw "$Dest\ exists but is not a git clone (interrupted setup?) -> delete $destPath and re-run"
    }
    if (-not (Test-Path $destPath)) {
        $login = gh api user -q .login
        if ($LASTEXITCODE -ne 0 -or -not $login) {
            throw 'could not determine the logged-in github user (gh api user failed)'
        }
        # does <login>/<repo> already exist, and is it a fork of upstream?
        $parent = gh api "repos/$login/$repoName" -q '.parent.full_name // ""' 2>$null
        $defaultOk = $true
        if ($LASTEXITCODE -eq 0 -and $parent -eq $Upstream) {
            $prompt = "found your existing fork $login/$repoName. enter = clone it, n = abort, or owner/repo to use a different fork"
        } elseif ($LASTEXITCODE -eq 0) {
            $prompt = "$login/$repoName exists on github but is not a fork of $Upstream. n = abort, or owner/repo of a fork to use instead"
            $defaultOk = $false
        } else {
            $prompt = "will fork $Upstream to $login/$repoName and clone into $Dest\. enter = ok, n = abort, or owner/repo to fork/clone elsewhere (e.g. my-org/$repoName)"
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
                    if ($forkParent -ne $Upstream) {
                        Write-Warning "$answer is not marked as a fork of $Upstream on github, PRs from it may not work"
                    }
                    git clone "https://github.com/$answer.git" $Dest
                    if ($LASTEXITCODE -ne 0) {
                        throw "git clone of $answer failed"
                    }
                } else {
                    $owner, $repo = $answer -split '/'
                    if ($repo -ne $repoName) {
                        throw "$answer not found on github (gh can only create the fork named $repoName) -> create it first or use <owner>/$repoName"
                    }
                    gh repo fork $Upstream --org $owner --clone -- $Dest
                    if ($LASTEXITCODE -ne 0) {
                        throw "gh repo fork --org $owner failed"
                    }
                }
            } elseif ($answer -match '^[nN]') {
                throw 'stopped before forking -> re-run setup.ps1 when ready'
            } elseif ($answer -eq '' -or $answer -match '^[yY]([eE][sS])?$') {
                if (-not $defaultOk) {
                    throw "$login/$repoName is not a fork of $Upstream -> re-run and enter an owner/repo fork to use instead"
                }
                gh repo fork $Upstream --clone -- $Dest
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

    Add-SafeDirectory $destPath

    # idempotent remote repair: origin = fork (left as gh set it), upstream stays canonical
    Push-Location $destPath
    try {
        if ((git remote) -notcontains 'upstream') {
            git remote add upstream "https://github.com/$Upstream.git"
        }
        git remote set-url upstream "https://github.com/$Upstream.git"
        if ($LASTEXITCODE -ne 0) {
            throw "failed to configure upstream remote in $Dest\"
        }

        $originUrl = git remote get-url origin
        if ($originUrl -match "github\.com[:/]$Upstream") {
            Write-Warning "origin points at upstream ($originUrl), not a fork -> PRs from this clone won't work; fork $Upstream and update origin"
        }
    } finally {
        Pop-Location
    }
}

Initialize-ForkClone 'CyberDrain/CIPP' 'cipp'
Initialize-ForkClone 'CyberDrain/Craft' 'craft'

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

# /graphify sessions need the skill registered with claude code (one-time, writes ~/.claude)
$claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
if (-not (Test-Path (Join-Path $claudeDir 'skills\graphify\SKILL.md'))) {
    try { $ans = Read-Host 'graphify skill not registered with Claude Code, register now? [Y/n]' } catch { $ans = 'n' }
    if ($ans -match '^[nN]') {
        Write-Host 'skipped, register later with: python -m graphify install --platform claude'
    } else {
        python -m graphify install --platform claude
        if ($LASTEXITCODE -ne 0) {
            throw 'graphify install failed'
        }
    }
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
