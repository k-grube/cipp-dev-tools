# cipp-dev-tools

one-clone bootstrap for [CIPP](https://github.com/CyberDrain/CIPP) monorepo local development, with a code knowledge graph for AI-assisted work.

## quick start

```powershell
git clone https://github.com/k-grube/cipp-dev-tools
cd cipp-dev-tools
.\setup.ps1     # forks + clones CyberDrain/CIPP into cipp\, installs pinned graphify, builds the graph
.\dev.ps1       # launches the local dev stack -> http://localhost:5196
```

macos: `./setup.sh` then `./dev.sh` (same flow; graphify goes into `.venv`, tabs open in Terminal.app).

first setup run builds the code graph cold (a few minutes); pass `-SkipGraph` / `--skip-graph` to defer it.

prereqs: PowerShell 7.2+ (pwsh), git, gh (authed), Docker Desktop, node + yarn, python 3. windows also needs Windows Terminal; macos installs pwsh via `brew install --cask powershell`.

## what you get

- `cipp\` - monorepo clone, origin = your fork of CyberDrain/CIPP, upstream = CyberDrain (PR-ready)
- local dev stack via upstream's own `build\` tooling (azurite, CRAFT api container, module watcher, frontend dev server)
- `graphify-out\graph.json` - directed knowledge graph of frontend + backend incl. `http_calls` edges mapping `/api/X` calls to `Invoke-X` functions
- `CLAUDE.md` so Claude Code sessions know all of the above

## daily commands

| command | what |
|---|---|
| `dev.ps1` / `dev.sh` | launch the dev environment |
| `graph-tools\update-graph.ps1` / `.sh` | refresh the graph after code changes (~10s) |
| `graph-tools\update-graph.ps1 --cluster` | + re-cluster and regenerate GRAPH_REPORT.md |
| `graph-tools\rebuild-graph.ps1` / `.sh` | full graph rebuild |

personal docker tweaks: drop a `docker-compose.override.yml` at the repo root (gitignored), `dev.ps1` picks it up.

## notes

- `graphifyy` is pinned to 0.9.12 on purpose - `spec\graphify-internals.md` explains what must be re-verified before bumping
- fresh clones build an AST+routes graph; doc-derived semantic content needs a one-time `/graphify` session in Claude Code
