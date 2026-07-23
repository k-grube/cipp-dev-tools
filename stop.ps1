#Requires -Version 7.2
# stops the stack dev.ps1 started: compose services, module watcher, frontend dev server
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$build = Join-Path $root 'cipp\build'
if (-not (Test-Path $build)) {
    throw 'cipp\ missing, nothing to stop'
}

# same -f chain as dev.ps1 so compose resolves the same project
$override = Join-Path $root 'docker-compose.override.yml'
$composeFiles = @('-f', 'docker-compose-no-frontend.yml')
if (Test-Path $override) {
    $composeFiles += @('-f', $override)
}
docker info *> $null
if ($LASTEXITCODE -eq 0) {
    Push-Location $build
    try {
        # keeps the cipp-ng_azurite-data volume, azurite state survives restarts
        docker compose @composeFiles down
    } finally {
        Pop-Location
    }
} else {
    Write-Warning 'docker not running, skipping compose down'
}

# watcher tab runs pwsh -EncodedCommand, decode to find it
$watchers = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" | Where-Object {
    $cl = $_.CommandLine
    if ($cl -match 'Watch-Cipp-Dev-Modules') {
        return $true
    }
    if ($cl -match '-EncodedCommand\s+([A-Za-z0-9+/=]+)') {
        try {
            return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1])) -match 'Watch-Cipp-Dev-Modules'
        } catch {
            return $false
        }
    }
    $false
}
foreach ($w in $watchers) {
    Stop-Process -Id $w.ProcessId -ErrorAction SilentlyContinue
}
if ($watchers) {
    Write-Host 'stopped module watcher'
}

$frontendPids = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
foreach ($fp in $frontendPids) {
    Stop-Process -Id $fp -ErrorAction SilentlyContinue
}
if ($frontendPids) {
    Write-Host "stopped frontend dev server (pid $($frontendPids -join ', '))"
}

# esbuild service daemons outlive a hard kill of the dev server, sweep this workspace's only
$esbuild = Get-Process esbuild -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like (Join-Path $root 'cipp\frontend\node_modules\*') }
foreach ($e in $esbuild) {
    Stop-Process -Id $e.Id -Force -ErrorAction SilentlyContinue
}
if ($esbuild) {
    Write-Host "stopped orphaned esbuild (pid $($esbuild.Id -join ', '))"
}

Write-Host 'dev stack stopped'
