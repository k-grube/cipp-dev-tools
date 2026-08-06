#Requires -Version 7.2
param([switch]$NoStorybook)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cipp = Join-Path $root 'CIPP'
if (-not (Test-Path $cipp)) {
    throw 'cipp\ missing -> run setup.ps1 first'
}
$launcher = Join-Path $cipp 'build\tools\Start-Cipp-Dev-Windows-docker.ps1'
if (-not (Test-Path $launcher)) {
    throw "upstream launcher not found at $launcher (monorepo layout changed?)"
}
# docker engine check before any tab launches, otherwise the stack half-starts
docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'docker desktop not running, start it (waiting, ctrl+c to abort)...' -ForegroundColor Yellow
    while ($true) {
        Start-Sleep -Seconds 3
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            break
        }
    }
}

# free the frontend dev ports (upstream launcher kills all node, too broad)
$stalePorts = @(3000)
if (-not $NoStorybook) {
    $stalePorts += 6006
}
$fePids = Get-NetTCPConnection -LocalPort $stalePorts -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
if ($fePids) {
    Stop-Process -Id $fePids -ErrorAction SilentlyContinue
    Wait-Process -Id $fePids -ErrorAction SilentlyContinue -Timeout 5
}

# fail fast on blocked ports, name the holder (container name when docker owns it)
# 3000 = frontend, 5196 = craft api, 6006 = storybook, 10000-10002 = azurite
$checkPorts = @(3000, 5196, 10000, 10001, 10002)
if (-not $NoStorybook) {
    $checkPorts += 6006
}
$blocked = foreach ($port in $checkPorts) {
    $conns = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    if (-not $conns) {
        continue
    }
    $owners = foreach ($ownerPid in ($conns.OwningProcess | Select-Object -Unique)) {
        $proc = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
        if ($proc) {
            '{0} (pid {1})' -f $proc.ProcessName, $ownerPid
        } else {
            "pid $ownerPid"
        }
    }
    # --filter publish resolves collapsed ranges like 10000-10002->
    $containers = @(docker ps --filter "publish=$port" --format '{{.Names}}' 2>$null)
    if ($containers) {
        $owners = @($owners) + "container $($containers -join ', ') -> stop.ps1"
    }
    "  ${port}: $($owners -join ', ')"
}
if ($blocked) {
    throw "port(s) in use:`n$($blocked -join "`n")"
}

$frontendPath = Join-Path $cipp 'frontend'
$enc = { param($s) [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s)) }
# --mutex network serializes this install against the frontend tab's
$storybookCommand = 'try { yarn install --network-timeout 500000 --mutex network; yarn storybook } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'

$override = Join-Path $root 'docker-compose.override.yml'
if (-not (Test-Path $override)) {
    if (-not $NoStorybook) {
        Get-Command wt -ErrorAction Stop | Out-Null
        wt --title 'CIPP Storybook' -d $frontendPath pwsh -EncodedCommand (& $enc $storybookCommand)
        Write-Host "`n  Storybook: http://localhost:6006" -ForegroundColor Green
    }
    & $launcher @args
    exit $LASTEXITCODE
}

# override mode: upstream invokes compose with explicit -f, which disables automatic
# docker-compose.override.yml merging, so chain the files ourselves for the docker tab
# and reuse upstream's module-watcher + frontend tabs verbatim
Write-Warning 'override mode: bypassing upstream launcher for the docker tab (drift risk if upstream changes its compose flow); frees port 3000 for the frontend dev server'
Get-Command wt -ErrorAction Stop | Out-Null
$dockerPath = Join-Path $cipp 'build'
$frontendCommand = 'try { yarn install --network-timeout 500000 --mutex network; yarn run dev } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$dockerCommand = "try { ./tools/build-dev-modules.ps1; docker compose -f docker-compose-no-frontend.yml -f `"$override`" up --pull always --watch } catch { Write-Error `$_.Exception.Message } finally { Read-Host 'Press Enter to exit' }"
$watcherCommand = 'try { ./tools/Watch-Cipp-Dev-Modules.ps1 -SkipInitialBuild } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$storybookTab = @()
if (-not $NoStorybook) {
    $storybookTab = @(';', 'new-tab', '--title', 'CIPP Storybook', '-d', $frontendPath, 'pwsh', '-EncodedCommand', (& $enc $storybookCommand))
}
docker volume create cipp-ng_azurite-data | Out-Null
wt --title CIPP-Docker -d $dockerPath pwsh -EncodedCommand (& $enc $dockerCommand)`; new-tab --title 'CIPP Modules' -d $dockerPath pwsh -EncodedCommand (& $enc $watcherCommand)`; new-tab --title 'CIPP Frontend' -d $frontendPath pwsh -EncodedCommand (& $enc $frontendCommand) @storybookTab
Write-Host "`n  API + Frontend: http://localhost:5196" -ForegroundColor Green
if (-not $NoStorybook) {
    Write-Host '  Storybook:      http://localhost:6006' -ForegroundColor Green
}
