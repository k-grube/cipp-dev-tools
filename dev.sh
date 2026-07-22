#!/usr/bin/env bash
# macos dev launcher. upstream only ships the Windows Terminal launcher
# (Start-Cipp-Dev-Windows-docker.ps1), so this mirrors its flow in Terminal.app
# windows (drift risk if upstream changes its compose flow)
set -euo pipefail
[ "$(uname)" = "Darwin" ] || { echo 'dev.sh is macos-only, use dev.ps1 on windows' >&2; exit 1; }
root="$(cd "$(dirname "$0")" && pwd)"
cipp="$root/cipp"
[ -d "$cipp" ] || { echo 'cipp/ missing -> run setup.sh first' >&2; exit 1; }
launcher_ref="$cipp/build/tools/Start-Cipp-Dev-Windows-docker.ps1"
[ -f "$launcher_ref" ] || { echo "upstream launcher not found at $launcher_ref (monorepo layout changed?)" >&2; exit 1; }
command -v pwsh >/dev/null 2>&1 || { echo 'missing pwsh -> brew install --cask powershell' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'docker desktop not running' >&2; exit 1; }

build="$cipp/build"
frontend="$cipp/frontend"
override="$root/docker-compose.override.yml"
compose_files="-f docker-compose-no-frontend.yml"
if [ -f "$override" ]; then
    compose_files="$compose_files -f '$override'"
fi

# mirrors upstream launcher: stop stray node processes, precreate azurite volume
pkill -x node 2>/dev/null || true
docker volume create cipp-ng_azurite-data >/dev/null

tab() { # title, dir, command (command must not contain double quotes)
    osascript >/dev/null <<EOF
tell application "Terminal"
    activate
    do script "printf '\\\\e]1;$1\\\\a'; cd '$2' && $3"
end tell
EOF
}

tab 'CIPP Docker'   "$build"    "pwsh -File tools/build-dev-modules.ps1 && docker compose $compose_files up --pull always --watch"
tab 'CIPP Modules'  "$build"    "pwsh -File tools/Watch-Cipp-Dev-Modules.ps1 -SkipInitialBuild"
tab 'CIPP Frontend' "$frontend" "yarn install --network-timeout 500000 && yarn run dev"

echo
echo '  API + Frontend: http://localhost:5196'
