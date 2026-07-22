# cipp-dev-tools workspace

bootstrap workspace for CIPP monorepo dev. `cipp\` is the monorepo clone (origin = your fork of CyberDrain/CIPP, upstream = CyberDrain/CIPP), gitignored here.

## dev environment

- `dev.ps1` launches the full local stack (azurite + CRAFT api container + module watcher + yarn frontend), everything at http://localhost:5196
- personal tweaks: drop a gitignored `docker-compose.override.yml` at this root, dev.ps1 chains it (upstream's own launcher would ignore it, explicit -f disables auto-merge)
- `setup.ps1` is idempotent, re-run to repair prereqs/remotes
- macos equivalents: `setup.sh` / `dev.sh` / `graph-tools\*.sh` (graphify in `.venv`, dev tabs via Terminal.app; dev.sh reimplements the upstream launcher flow, upstream ships windows-only)

## knowledge graph

`graphify-out\graph.json` is a directed graph of the monorepo (AST + `http_calls` edges linking frontend `/api/X` calls to backend `Invoke-X` functions). check it before grepping. `graphify-out\GRAPH_REPORT.md` has the community map, `route-orphans.json` the unresolved routes.

- after code changes: `graph-tools\update-graph.ps1` (~10s, no LLM). `--cluster` re-clusters + regenerates the report
- full rebuild: `graph-tools\rebuild-graph.ps1` (needed when update refuses with the shrink-guard error, or after `.graphifyignore` changes)
- doc/image changes are not picked up by these scripts, a /graphify session adds semantic content (one-time after a fresh clone too)

## rules

- never run the /graphify skill or `graphify extract` against `cipp\` directly, work from this root, outputs stay here
- detect scope: `.graphifyignore` at this root (committed, root-anchored, graphify's fnmatch `*` crosses `/`). new vendored modules under `cipp\backend\Modules\` need an entry
- the `!cipp` line in `.graphifyignore` is load-bearing (workspace .gitignore excludes cipp/ and detect merges gitignores), never remove it
- route edges carry synthetic `source_file` `graph-tools/route-links` (real path in `source_location`), never retag with real paths (build_merge replace-on-re-extract would wipe those files' AST nodes)
- graphifyy is pinned ==0.9.12, `spec\graphify-internals.md` lists the internals the toolkit depends on, re-verify before any bump
- `spec\cipp-openapi-v2.json` is an auto-generated OpenAPI snapshot of the CIPP API (2026-03-02, ~80% endpoint coverage), useful for request/response shapes but the graph + code are authoritative
- contributions: branch on your fork of CyberDrain/CIPP, PR to CyberDrain/CIPP `dev` (never `main`, release-only). commit in `cipp\` only when the user asks, suggest message and stop
