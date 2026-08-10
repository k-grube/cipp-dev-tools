#Requires -Version 7.2
# forwards to CIPP\frontend yarn scripts: .\test.ps1 [--watch|--unit|--storybook|--browser|--coverage] [vitest args]
$map = @{
    '--watch'     = 'test:watch';     '-w' = 'test:watch'
    '--unit'      = 'test:unit';      '-u' = 'test:unit'
    '--storybook' = 'test:storybook'; '-s' = 'test:storybook'
    '--browser'   = 'test:browser';   '-b' = 'test:browser'
    '--coverage'  = 'test:coverage';  '-c' = 'test:coverage'
}
$script = 'test'
$rest = @()
foreach ($a in $args) {
    if ($map.ContainsKey($a)) {
        $script = $map[$a]
    } elseif ($a -in '--help', '-h') {
        Write-Host 'usage: .\test.ps1 [--watch|--unit|--storybook|--browser|--coverage] [vitest args, e.g. a test file or -t "name"]'
        Write-Host 'default (no flag): both projects (unit jsdom + storybook chromium)'
        exit 0
    } else {
        $rest += $a
    }
}
Push-Location (Join-Path $PSScriptRoot 'CIPP' 'frontend')
try {
    # yarn 1 forwards extra args as-is, an explicit -- warns and gets passed through
    yarn run $script @rest
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
