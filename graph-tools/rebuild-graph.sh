#!/usr/bin/env bash
# macos wrapper, mirrors rebuild-graph.ps1 (uses the setup.sh venv)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
py="$root/.venv/bin/python"
[ -x "$py" ] || { echo 'missing .venv -> run setup.sh first' >&2; exit 1; }
cd "$root"
"$py" graph-tools/rebuild.py
"$py" graph-tools/routelink.py
"$py" -m graphify export html
