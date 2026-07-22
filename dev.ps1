#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cipp = Join-Path $root 'cipp'
if (-not (Test-Path $cipp)) {
    throw 'cipp\ missing -> run setup.ps1 first'
}
$launcher = Join-Path $cipp 'build\tools\Start-Cipp-Dev-Windows-docker.ps1'
if (-not (Test-Path $launcher)) {
    throw "upstream launcher not found at $launcher (monorepo layout changed?)"
}
$override = Join-Path $root 'docker-compose.override.yml'
if (-not (Test-Path $override)) {
    & $launcher @args
    exit $LASTEXITCODE
}

# override mode: upstream invokes compose with explicit -f, which disables automatic
# docker-compose.override.yml merging, so chain the files ourselves for the docker tab
# and reuse upstream's module-watcher + frontend tabs verbatim
Write-Warning 'override mode: bypassing upstream launcher for the docker tab (drift risk if upstream changes its compose flow); frees port 3000 for the frontend dev server'
Get-Command wt -ErrorAction Stop | Out-Null
# free the frontend dev port (upstream launcher kills all node, too broad)
Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { Stop-Process -Id $_ -ErrorAction SilentlyContinue }
$frontendPath = Join-Path $cipp 'frontend'
$dockerPath = Join-Path $cipp 'build'
$frontendCommand = 'try { yarn install --network-timeout 500000; yarn run dev } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$dockerCommand = "try { ./tools/build-dev-modules.ps1; docker compose -f docker-compose-no-frontend.yml -f `"$override`" up --pull always --watch } catch { Write-Error `$_.Exception.Message } finally { Read-Host 'Press Enter to exit' }"
$watcherCommand = 'try { ./tools/Watch-Cipp-Dev-Modules.ps1 -SkipInitialBuild } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$enc = { param($s) [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s)) }
docker volume create cipp-ng_azurite-data | Out-Null
wt --title CIPP-Docker -d $dockerPath pwsh -EncodedCommand (& $enc $dockerCommand)`; new-tab --title 'CIPP Modules' -d $dockerPath pwsh -EncodedCommand (& $enc $watcherCommand)`; new-tab --title 'CIPP Frontend' -d $frontendPath pwsh -EncodedCommand (& $enc $frontendCommand)
Write-Host "`n  API + Frontend: http://localhost:5196" -ForegroundColor Green
