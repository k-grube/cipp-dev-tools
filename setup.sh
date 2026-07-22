#!/usr/bin/env bash
# macos setup, mirrors setup.ps1 (pass --skip-graph to defer the graph build)
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"

need() {
    command -v "$1" >/dev/null 2>&1 || { echo "missing prerequisite: $1 -> $2" >&2; exit 1; }
}
need git 'https://git-scm.com'
need gh 'brew install gh then: gh auth login'
need docker 'Docker Desktop: https://docker.com'
need node 'https://nodejs.org'
need yarn 'npm install -g yarn'
need python3 'https://python.org'
need pwsh 'brew install --cask powershell (upstream module builder + watcher are pwsh scripts)'

gh auth status >/dev/null 2>&1 || { echo 'gh not authenticated -> gh auth login' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'docker desktop not running' >&2; exit 1; }

cipp="$root/cipp"
if [ -d "$cipp" ] && [ ! -d "$cipp/.git" ]; then
    echo "cipp/ exists but is not a git clone (interrupted setup?) -> delete $cipp and re-run" >&2
    exit 1
fi
if [ ! -d "$cipp" ]; then
    # forks CyberDrain/CIPP under the authed user (reuses an existing fork), clones into cipp/
    (cd "$root" && gh repo fork CyberDrain/CIPP --clone -- cipp)
fi

# idempotent remote repair: origin = fork (left as gh set it), upstream = CyberDrain
(
    cd "$cipp"
    if ! git remote | grep -qx upstream; then
        git remote add upstream https://github.com/CyberDrain/CIPP.git
    fi
    git remote set-url upstream https://github.com/CyberDrain/CIPP.git
    origin_url="$(git remote get-url origin)"
    case "$origin_url" in
        *github.com[:/]CyberDrain/CIPP*)
            echo "warning: origin points at upstream ($origin_url), not a fork -> PRs from this clone won't work; fork CyberDrain/CIPP and update origin" >&2
            ;;
    esac
)

# graphify lives in .venv (brew python blocks global pip installs, PEP 668)
venv_py="$root/.venv/bin/python"
if [ ! -x "$venv_py" ]; then
    python3 -m venv "$root/.venv"
fi
if ! "$venv_py" -c 'import graphify' 2>/dev/null; then
    "$venv_py" -m pip install graphifyy==0.9.12
fi
"$venv_py" -c "import importlib.metadata as m; v = m.version('graphifyy'); assert v == '0.9.12', v; print('graphifyy', v)" \
    || { echo 'graphifyy version check failed, expected exactly 0.9.12' >&2; exit 1; }

if [ "${1:-}" != "--skip-graph" ]; then
    if [ -x "$root/graph-tools/rebuild-graph.sh" ]; then
        "$root/graph-tools/rebuild-graph.sh" \
            || { echo 'graph build failed -> fix the error above, then re-run setup.sh or run graph-tools/rebuild-graph.sh directly' >&2; exit 1; }
    else
        echo 'graph-tools not present yet, skipping graph build'
    fi
fi
echo 'setup complete'
