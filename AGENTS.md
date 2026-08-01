# cipp-dev-tools workspace

bootstrap workspace for CIPP monorepo dev. `CIPP\` is the monorepo clone (origin = your fork of CyberDrain/CIPP, upstream = CyberDrain/CIPP), gitignored here. `Craft\` is the Craft runtime clone (the C# host that serves the CIPP api container; same fork/upstream pattern against CyberDrain/Craft), also gitignored.

## dev environment

- `dev.ps1` launches the full local stack (azurite + Craft api container + module watcher + yarn frontend), everything at http://localhost:5196
- `stop.ps1` stops the stack (compose down with the same -f chain, module watcher, frontend on :3000; azurite volume kept)
- personal tweaks: drop a gitignored `docker-compose.override.yml` at this root, dev.ps1 / dev.sh chain it (upstream's own launcher would ignore it, explicit -f disables auto-merge)
- `setup.ps1` is idempotent, re-run to repair prereqs/remotes
- macos equivalents: `setup.sh` / `dev.sh` / `stop.sh` / `graph-tools\*.sh` (graphify in `.venv`, dev tabs via Terminal.app; dev.sh reimplements the upstream launcher flow, upstream ships windows-only)

## frontend tests

`frontend-tests\` mirrors the jsdom suite from the unmerged CIPP `feat/frontend-tests` branch so UI changes can be tested without waiting on the upstream PR. runs against the live `CIPP\frontend` working tree on any branch, nothing test-related enters CIPP PRs.

- run: `.\test.ps1` / `./test.sh` at this root (`--unit`, `--storybook`, `--watch`, `--browser`, `--coverage`, extra args pass to vitest), or npm scripts in `frontend-tests\`
- `src` is a junction into `CIPP\frontend\src`; `ensure-links.mjs` junctions react/mui/query/etc into local node_modules so both trees share one copy (dual react breaks hooks). both are gitignored, the test script recreates links
- deps come from `CIPP\frontend\node_modules`, so `yarn install` there first
- excluded from the graph (`.graphifyignore`). delete the mirror once upstream merges the tests PR

## knowledge graph

`graphify-out\graph.json` is a directed graph of the monorepo + craft runtime. AST nodes plus cross-repo link passes: `http_calls` edges (frontend `/api/X` -> backend `Invoke-X`, and frontend -> craft-served auth/setup routes), `bridge_calls` edges (backend ps1 `[Craft.Services.X]::Y()` -> craft C# bridge methods), and `external_api` nodes for the microsoft endpoints craft hits (graph.microsoft.com, login.microsoftonline.com, ...). check it before grepping. `graphify-out\GRAPH_REPORT.md` has the community map, `route-orphans.json` / `craft-orphans.json` the unresolved links.

- query it with `python graph-tools\query.py` (`find <text>` / `node <id|label>` / `path <from> <to>` / `trace <ApiEndpointName>`), don't hand-roll graph.json scripts. `trace` prints the frontend -> backend -> craft -> microsoft chain for an endpoint (macos: `.venv/bin/python graph-tools/query.py`)
- after code changes: `graph-tools\update-graph.ps1` (~10s, no LLM). `--cluster` re-clusters + regenerates the report
- full rebuild: `graph-tools\rebuild-graph.ps1` (needed when update refuses with the shrink-guard error, after `.graphifyignore` changes, or to drop deleted docs)
- doc changes are not picked up by these scripts: run a /graphify session (only changed docs re-extract, content-hash cache in `graphify-out\cache\semantic\`), then rebuild to merge
- graph.json + sidecars + the semantic cache are committed here, commit the refreshed files after updating so other clones skip the LLM recompute

## rules

- never run the /graphify skill or `graphify extract` against `CIPP\` or `Craft\` directly, work from this root, outputs stay here
- detect scope: `.graphifyignore` at this root (committed, root-anchored, graphify's fnmatch `*` crosses `/`). new vendored modules under `CIPP\backend\Modules\` need an entry
- the `!CIPP` and `!Craft` lines in `.graphifyignore` are load-bearing (workspace .gitignore excludes both clones and detect merges gitignores), never remove them
- link-pass edges carry synthetic `source_file` values `graph-tools/route-links` / `graph-tools/craft-links` (real path in `source_location`), never retag with real paths (build_merge replace-on-re-extract would wipe those files' AST nodes)
- graphifyy is pinned ==0.9.12, `spec\graphify-internals.md` lists the internals the toolkit depends on, re-verify before any bump
- `spec\cipp-openapi-v2.json` is an auto-generated OpenAPI snapshot of the CIPP API (2026-03-02, ~80% endpoint coverage), useful for request/response shapes but the graph + code are authoritative
- contributions: branch on your fork of CyberDrain/CIPP, PR to CyberDrain/CIPP `dev` (never `main`, release-only). commit in `CIPP\` only when the user asks, suggest message and stop
- `Craft\` is upstream-tracking for reading/tracing; treat commits there the same way (user asks first), craft PRs target CyberDrain/Craft `dev` like CIPP
