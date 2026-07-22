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
    login="$(gh api user -q .login)" || { echo 'could not determine the logged-in github user (gh api user failed)' >&2; exit 1; }
    # does <login>/CIPP already exist, and is it a fork of upstream?
    default_ok=1
    if parent="$(gh api "repos/$login/CIPP" -q '.parent.full_name // ""' 2>/dev/null)"; then
        if [ "$parent" = "CyberDrain/CIPP" ]; then
            prompt="found your existing fork $login/CIPP. enter = clone it, n = abort, or owner/repo to use a different fork: "
        else
            prompt="$login/CIPP exists on github but is not a fork of CyberDrain/CIPP. n = abort, or owner/repo of a fork to use instead: "
            default_ok=0
        fi
    else
        prompt="will fork CyberDrain/CIPP to $login/CIPP and clone into cipp/. enter = ok, n = abort, or owner/repo to fork/clone elsewhere (e.g. my-org/CIPP): "
    fi
    printf '%s' "$prompt"
    read -r answer || answer=''
    answer="${answer//\\//}"
    case "$answer" in
        */*)
            case "$answer" in
                */*/*|*' '*)
                    echo "unrecognized fork name '$answer' (expected owner/repo)" >&2; exit 1 ;;
            esac
            if fork_parent="$(gh api "repos/$answer" -q '.parent.full_name // ""' 2>/dev/null)"; then
                if [ "$fork_parent" != "CyberDrain/CIPP" ]; then
                    echo "warning: $answer is not marked as a fork of CyberDrain/CIPP on github, PRs from it may not work" >&2
                fi
                (cd "$root" && git clone "https://github.com/$answer.git" cipp)
            else
                owner="${answer%%/*}"
                repo="$(printf '%s' "${answer#*/}" | tr '[:upper:]' '[:lower:]')"
                if [ "$repo" != "cipp" ]; then
                    echo "$answer not found on github (gh can only create the fork named CIPP) -> create it first or use <owner>/CIPP" >&2
                    exit 1
                fi
                (cd "$root" && gh repo fork CyberDrain/CIPP --org "$owner" --clone -- cipp)
            fi ;;
        [Nn]*)
            echo 'stopped before forking -> re-run setup.sh when ready' >&2; exit 1 ;;
        ''|[Yy]|[Yy][Ee][Ss])
            if [ "$default_ok" != 1 ]; then
                echo "$login/CIPP is not a fork of CyberDrain/CIPP -> re-run and enter an owner/repo fork to use instead" >&2
                exit 1
            fi
            (cd "$root" && gh repo fork CyberDrain/CIPP --clone -- cipp) ;;
        *)
            echo "unrecognized answer '$answer' (expected enter, n, or owner/repo)" >&2; exit 1 ;;
    esac
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

# graphifyy needs python >=3.10
py_ok() {
    "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null
}

# graphify lives in .venv (brew python blocks global pip installs, PEP 668)
venv_py="$root/.venv/bin/python"
if [ -x "$venv_py" ] && ! py_ok "$venv_py"; then
    echo ".venv was built with python $("$venv_py" -c 'import platform; print(platform.python_version())'), graphifyy needs >=3.10 -> delete $root/.venv and re-run" >&2
    exit 1
fi
if [ ! -x "$venv_py" ]; then
    if ! py_ok python3; then
        echo "python3 is $(python3 -c 'import platform; print(platform.python_version())'), graphifyy needs >=3.10 -> brew install python, then re-run (python3 must resolve to >=3.10)" >&2
        exit 1
    fi
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
