#Requires -Version 7.2
# forwards to frontend-tests npm scripts: .\test.ps1 [--watch|--unit|--storybook|--browser] [vitest args]
$map = @{
    '--watch'     = 'test:watch';     '-w' = 'test:watch'
    '--unit'      = 'test:unit';      '-u' = 'test:unit'
    '--storybook' = 'test:storybook'; '-s' = 'test:storybook'
    '--browser'   = 'test:browser';   '-b' = 'test:browser'
}
$script = 'test'
$rest = @()
foreach ($a in $args) {
    if ($map.ContainsKey($a)) {
        $script = $map[$a]
    } elseif ($a -in '--help', '-h') {
        Write-Host 'usage: .\test.ps1 [--watch|--unit|--storybook|--browser] [vitest args, e.g. a test file or -t "name"]'
        Write-Host 'no flag runs both projects (unit jsdom + storybook chromium)'
        exit 0
    } else {
        $rest += $a
    }
}
Push-Location (Join-Path $PSScriptRoot 'frontend-tests')
try {
    if ($rest.Count) {
        npm run $script -- @rest
    } else {
        npm run $script
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
