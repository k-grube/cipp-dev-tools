#!/usr/bin/env bash
# stops the stack dev.sh started: compose services, module watcher, frontend dev server
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
build="$root/cipp/build"
[ -d "$build" ] || { echo 'cipp/ missing, nothing to stop' >&2; exit 1; }

# same -f chain as dev.sh so compose resolves the same project
override="$root/docker-compose.override.yml"
compose_files=(-f docker-compose-no-frontend.yml)
if [ -f "$override" ]; then
    compose_files+=(-f "$override")
fi
if docker info >/dev/null 2>&1; then
    # keeps the cipp-ng_azurite-data volume, azurite state survives restarts
    (cd "$build" && docker compose "${compose_files[@]}" down)
else
    echo 'docker not running, skipping compose down' >&2
fi

if pkill -f 'Watch-Cipp-Dev-Modules.ps1' 2>/dev/null; then
    echo 'stopped module watcher'
fi

pids="$(lsof -ti tcp:3000 -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$pids" ]; then
    kill $pids
    echo "stopped frontend dev server (pid $pids)"
fi

echo 'dev stack stopped'
