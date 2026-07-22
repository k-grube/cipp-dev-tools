Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    python graph-tools\rebuild.py && python graph-tools\routelink.py && python -m graphify export html
    $ok = $?
} finally {
    Pop-Location
}
if (-not $ok) { exit 1 }
