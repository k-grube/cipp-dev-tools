Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    python graph-tools\update.py @args && python graph-tools\routelink.py && python -m graphify export html
    $ok = $?
} finally {
    Pop-Location
}
if (-not $ok) { exit 1 }
