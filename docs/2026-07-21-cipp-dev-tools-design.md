# cipp-dev-tools: bootstrap repo for CIPP monorepo local dev + knowledge graph

date: 2026-07-21
status: approved (approach A+C: thin wrapper over upstream dev tooling, with local override hook)

## Problem

Upstream CIPP migrated to a monorepo (`CyberDrain/CIPP`: `frontend/` + `backend/` + `build/`). The existing local dev workspace (`C:\github\cipp-parent`, two-repo layout) and its graph-tools toolkit target the old split repos. Contributors need a one-clone bootstrap that stands up the monorepo dev environment and the knowledge graph.

## Vision

Clone `k-grube/cipp-dev-tools`, run `setup.ps1`, and you have: a fork-wired monorepo clone, the upstream docker dev environment ready to launch, a queryable knowledge graph of frontend + backend with FE/BE route links, and a `CLAUDE.md` so agent sessions know all of it.

## Decisions (locked)

- tools repo IS the workspace root; monorepo cloned inside it at `cipp\` (gitignored)
- fork-aware clone: `gh repo fork CyberDrain/CIPP --clone` -> origin = user fork, upstream = CyberDrain
- dev environment delegated to upstream `cipp\build\tools\` scripts; we wrap, never vendor
- local `docker-compose.override.yml` drop-in supported (gitignored)
- cipp-parent stays untouched as legacy; WIP branches port on demand, out of scope here
- graphifyy pinned `==0.9.12` (toolkit verified against its internals; see graphify-internals doc)

## Repo layout

```
cipp-dev-tools/                # k-grube/cipp-dev-tools, cloned anywhere (e.g. C:\github\cipp-dev)
  setup.ps1                    # one-time bootstrap
  dev.ps1                      # daily driver: launch dev environment
  graph-tools\
    common.py                  # ported, ROOT = repo root
    routelink.py               # ported, scans cipp\frontend\src
    rebuild.py                 # ported
    update.py                  # ported
    rebuild-graph.ps1
    update-graph.ps1
  .graphifyignore              # committed (workspace root = repo root)
  .gitignore                   # cipp/, graphify-out/, docker-compose.override.yml, __pycache__/
  CLAUDE.md                    # committed agent context
  README.md
  docs\
    graphify-internals.md      # the 0.9.12 quirks the toolkit depends on (why the pin is strict)
    <this spec + plan, migrated>
  cipp\                        # gitignored: the monorepo clone (created by setup.ps1)
  graphify-out\                # gitignored: graph outputs
```

## Components

### setup.ps1 (one-time)

1. prereq checks, fail with actionable message per miss: git, gh (authed: `gh auth status`), docker desktop running, `wt` (Windows Terminal, upstream dev script requires it), node + yarn, python 3.x
2. clone: if `cipp\` missing -> `gh repo fork CyberDrain/CIPP --clone -- cipp` (creates fork if none; if fork exists, clones it), then ensure `upstream` remote = `https://github.com/CyberDrain/CIPP.git`. Idempotent: existing `cipp\` dir -> verify remotes, fix if wrong, don't reclone
3. `pip install graphifyy==0.9.12` (exact pin) if not importable
4. offer initial graph build: `-SkipGraph` flag skips; default runs `graph-tools\rebuild-graph.ps1` (cold AST build, a few minutes, no LLM)
5. idempotent throughout; re-running repairs a broken setup

### dev.ps1 (daily)

- no override present (common case): run `cipp\build\tools\Start-Cipp-Dev-Windows-docker.ps1` untouched; upstream owns the environment (azurite + CRAFT api container with backend bind-mount + module watcher + yarn frontend, http://localhost:5196)
- override present (`docker-compose.override.yml` at repo root, gitignored): upstream's script invokes compose with explicit `-f docker-compose-no-frontend.yml`, which disables docker's automatic override merging, so the hook must chain files itself. dev.ps1 sets `$env:COMPOSE_FILE` is NOT sufficient (explicit -f wins); instead dev.ps1 replicates only the docker tab's compose call as `docker compose -f cipp\build\docker-compose-no-frontend.yml -f docker-compose.override.yml up --pull always --watch` and reuses upstream's module-watcher and frontend commands verbatim for the other tabs. This is the single sanctioned deviation from "never vendor" - contained to one compose invocation, and dev.ps1 prints a warning that override mode bypasses upstream's launcher (drift risk is visible, not silent)
- passthrough `@args` in the no-override path

### graph-tools port

Mechanical adaptation of the proven cipp-parent toolkit:

- `common.py`: ROOT stays `Path(__file__).resolve().parent.parent` (= repo root); `clean_repo_stat_caches` targets `cipp\graphify-out` (detect writes stat cache into scan root; scan root IS repo root now, so the stray-dir case is `cipp\` only if a subscan ever runs - keep the guard, repoint it)
- `routelink.py`: scan path `ROOT / 'cipp' / 'frontend' / 'src'`; backend node source_file prefix check updated from `CIPP-API/Modules/CIPPHTTP` to `cipp/backend/Modules/CIPPHTTP` (verify actual layout at port time); ROUTE_SOURCE constant unchanged
- `rebuild.py` / `update.py`: unchanged logic; single-repo corpus now (no two-repo merge concerns); manifest root stays ROOT
- `.graphifyignore` (committed): root-anchored patterns - `/graph-tools`, `/graphify-out`, `/docs`, `/cipp/build` (dev tooling, not app code - decide at port time whether to include), `/cipp/frontend/public`, vendored `/cipp/backend/Modules/<third-party>` entries (enumerate at port time; expect the same set: MicrosoftTeams, AzBobbyTables, PassPushPosh, HuduAPI, DNSHealth, AzureFunctions.PowerShell.Durable.SDK, plus Tools/ModuleBuilder if present)
- nested-ignore behavior verified in the old toolkit carries over: the monorepo's own `.gitignore`s are NOT read when scanning from the workspace root; our committed `.graphifyignore` is the single source of scope truth

### CLAUDE.md (committed)

Covers: the graph exists, query before grepping; `update-graph.ps1` after code changes (`--cluster` variant); `rebuild-graph.ps1` when the shrink guard refuses; doc changes need a /graphify session; never scan `cipp\` directly; route-edge source_file invariant; fork/PR workflow (branch on origin fork, PR to upstream - target branch verified at port time from upstream CONTRIBUTING); `dev.ps1` to launch the environment. Loads for agent sessions inside `cipp\` too (ancestor-directory loading).

### docs/graphify-internals.md

The 0.9.12 behaviors the toolkit depends on, so a future version bump knows what to re-verify: fnmatch `*` crosses `/` + anchored-pattern semantics; `build_merge` does not persist (caller must to_json); `build_merge` replace-on-re-extract keyed on source_file; `to_json` `force=`/`community_labels=` params and the #479 node-count shrink guard; html export reads `.graphify_analysis.json` + `.graphify_labels.json` sidecars; detect ignores nested `.gitignore`/`.graphifyignore` during parent scans; multiprocessing `__main__` guard requirement on Windows.

### Semantic cache seed (optional, decide at implementation)

Doc-derived graph nodes come from the local semantic extraction cache; a fresh clone rebuilds without them until a /graphify session runs once. If the cache entries for the monorepo's docs are small and file-hash-keyed, ship them under `graph-tools\semantic-seed\` and have rebuild copy them into `graphify-out\cache`. If upstream docs have already drifted from any cache we can produce, skip the seed and document the one-time /graphify step instead.

## Error handling

- setup.ps1: each prereq failure names the missing tool and the install command/link; clone failures surface gh's error verbatim; never continues past a failed step
- dev.ps1: if `cipp\` missing -> "run setup.ps1 first"
- graph scripts: unchanged from the proven toolkit (shrink guard, manifest-unstamped retry, loud SystemExits)

## Verification

- setup on a clean machine-sim (delete cipp\ + graphify-out\, rerun): completes, remotes correct (origin=k-grube fork, upstream=CyberDrain), graph builds
- rebuilt graph sanity: directed, frontend+backend nodes present, http_calls edges present (count reported), vendored modules absent
- update-graph.ps1 no-op: seconds, "up to date"
- dev.ps1: launches upstream script (manual verification that the environment comes up; automated check limited to script-exists + docker running)
- CLAUDE.md accuracy: every command in it actually exists and runs

## Migration notes (this machine)

- new workspace: C:\github\cipp-dev-tools (created locally first, pushed to k-grube/cipp-dev-tools), run setup
- cipp-parent: untouched, remains the legacy two-repo workspace; its graph and graph-tools keep working for the old branches until retired
- old WIP branches: ported individually later (cherry-pick + path rewrite to frontend/ prefix), explicitly out of scope

## Out of scope

- porting the 8 WIP branches from cipp-parent
- generalizing the toolkit beyond CIPP
- auto-update hooks (post-commit etc.)
- vendoring/patching upstream dev environment scripts
- CI for cipp-dev-tools

## Open questions (resolve at implementation, not blockers)

- monorepo PR target branch (main vs dev) - read upstream CONTRIBUTING/docs at port time
- exact vendored-module list under cipp\backend\Modules
- whether cipp\build belongs in the graph corpus (lean toward exclude: tooling, not app code)
- semantic cache seed viability (see above)
