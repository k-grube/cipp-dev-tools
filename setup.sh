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

# git refuses repos owned by another user (dubious ownership), sudo/elevated shells mask the
# error so add unconditionally, dedupe keeps re-runs clean
add_safe_directory() {
    git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$1" \
        || git config --global --add safe.directory "$1"
}
add_safe_directory "$root"

# fork-prompt + clone + remote repair, shared by cipp and craft
init_fork_clone() { # upstream owner/repo, dest dir
    local upstream="$1" dest="$2"
    local repo_name="${upstream#*/}"
    local dest_path="$root/$dest"
    local login parent default_ok prompt answer fork_parent owner repo origin_url
    if [ -d "$dest_path" ] && [ ! -d "$dest_path/.git" ]; then
        echo "$dest/ exists but is not a git clone (interrupted setup?) -> delete $dest_path and re-run" >&2
        exit 1
    fi
    if [ ! -d "$dest_path" ]; then
        login="$(gh api user -q .login)" || { echo 'could not determine the logged-in github user (gh api user failed)' >&2; exit 1; }
        # does <login>/<repo> already exist, and is it a fork of upstream?
        default_ok=1
        if parent="$(gh api "repos/$login/$repo_name" -q '.parent.full_name // ""' 2>/dev/null)"; then
            if [ "$parent" = "$upstream" ]; then
                prompt="found your existing fork $login/$repo_name. enter = clone it, n = abort, or owner/repo to use a different fork: "
            else
                prompt="$login/$repo_name exists on github but is not a fork of $upstream. n = abort, or owner/repo of a fork to use instead: "
                default_ok=0
            fi
        else
            prompt="will fork $upstream to $login/$repo_name and clone into $dest/. enter = ok, n = abort, or owner/repo to fork/clone elsewhere (e.g. my-org/$repo_name): "
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
                    if [ "$fork_parent" != "$upstream" ]; then
                        echo "warning: $answer is not marked as a fork of $upstream on github, PRs from it may not work" >&2
                    fi
                    (cd "$root" && git clone "https://github.com/$answer.git" "$dest")
                else
                    owner="${answer%%/*}"
                    repo="$(printf '%s' "${answer#*/}" | tr '[:upper:]' '[:lower:]')"
                    if [ "$repo" != "$(printf '%s' "$repo_name" | tr '[:upper:]' '[:lower:]')" ]; then
                        echo "$answer not found on github (gh can only create the fork named $repo_name) -> create it first or use <owner>/$repo_name" >&2
                        exit 1
                    fi
                    (cd "$root" && gh repo fork "$upstream" --org "$owner" --clone -- "$dest")
                fi ;;
            [Nn]*)
                echo 'stopped before forking -> re-run setup.sh when ready' >&2; exit 1 ;;
            ''|[Yy]|[Yy][Ee][Ss])
                if [ "$default_ok" != 1 ]; then
                    echo "$login/$repo_name is not a fork of $upstream -> re-run and enter an owner/repo fork to use instead" >&2
                    exit 1
                fi
                (cd "$root" && gh repo fork "$upstream" --clone -- "$dest") ;;
            *)
                echo "unrecognized answer '$answer' (expected enter, n, or owner/repo)" >&2; exit 1 ;;
        esac
    fi

    add_safe_directory "$dest_path"

    # idempotent remote repair: origin = fork (left as gh set it), upstream stays canonical
    (
        cd "$dest_path"
        if ! git remote | grep -qx upstream; then
            git remote add upstream "https://github.com/$upstream.git"
        fi
        git remote set-url upstream "https://github.com/$upstream.git"
        origin_url="$(git remote get-url origin)"
        case "$origin_url" in
            *github.com[:/]"$upstream"*)
                echo "warning: origin points at upstream ($origin_url), not a fork -> PRs from this clone won't work; fork $upstream and update origin" >&2
                ;;
        esac
    )
}

init_fork_clone 'CyberDrain/CIPP' 'cipp'
init_fork_clone 'CyberDrain/Craft' 'craft'

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
