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
if ! docker info >/dev/null 2>&1; then
    echo 'docker desktop not running, start it (waiting, ctrl+c to abort)...'
    until docker info >/dev/null 2>&1; do
        sleep 3
    done
fi

build="$cipp/build"
frontend="$cipp/frontend"
override="$root/docker-compose.override.yml"
compose_files="-f docker-compose-no-frontend.yml"
if [ -f "$override" ]; then
    compose_files="$compose_files -f '$override'"
fi

# free the frontend dev port (upstream launcher kills all node, too broad)
pids="$(lsof -ti tcp:3000 -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$pids" ]; then
    echo "killing listener(s) on :3000 (pid $pids)"
    kill $pids
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        lsof -ti tcp:3000 -sTCP:LISTEN >/dev/null 2>&1 || break
        sleep 0.2
    done
fi

# fail fast on blocked ports, name the holder (container name when docker owns it)
# 3000 = frontend, 5196 = craft api, 10000-10002 = azurite
blocked=''
for port in 3000 5196 10000 10001 10002; do
    holders="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1" (pid "$2")"}' | sort -u | paste -sd, - || true)"
    [ -n "$holders" ] || continue
    # --filter publish resolves collapsed ranges like 10000-10002->
    containers="$(docker ps --filter "publish=$port" --format '{{.Names}}' 2>/dev/null | sort -u | paste -sd, - || true)"
    if [ -n "$containers" ]; then
        holders="$holders, container $containers -> stop.sh"
    fi
    blocked="${blocked}  ${port}: ${holders}\n"
done
if [ -n "$blocked" ]; then
    printf 'port(s) in use:\n%b' "$blocked" >&2
    exit 1
fi
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
