# cipp-dev-tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `C:\github\cipp-dev-tools` - a one-clone bootstrap repo (published to k-grube/cipp-dev-tools) for CIPP monorepo local dev: fork-wired clone, upstream docker dev environment, ported knowledge-graph toolkit, agent context.

**Architecture:** Workspace-as-repo: the tools repo is the workspace root; the monorepo clone (`cipp\`) and graph outputs (`graphify-out\`) live inside it, gitignored. Dev environment delegates to upstream `cipp\build\tools\`; graph toolkit is a mechanical port of the proven cipp-parent `graph-tools\`.

**Tech Stack:** PowerShell 7, Python 3.14 + graphifyy==0.9.12 (exact pin), gh CLI, git, upstream docker compose stack.

## Global Constraints

- Spec: `C:\github\cipp-parent\docs\superpowers\specs\2026-07-21-cipp-dev-tools-design.md` - read it before starting
- Workspace: `C:\github\cipp-dev-tools`. THIS repo gets commits (new scaffolding repo, main branch). NEVER run git commit/branch/push inside `cipp\` (the monorepo clone) or inside `C:\github\cipp-parent\CIPP*`
- Commit style: `type: terse lowercase subject`, NO Co-Authored-By trailer, body only when the why isn't in the diff
- Push/publish happens ONLY in Task 5 (user has authorized creating k-grube/cipp-dev-tools and pushing; nothing is pushed before the repo content is complete)
- Source toolkit to port: `C:\github\cipp-parent\graph-tools\` - copy files, then apply the exact edits listed; do not rewrite from scratch
- graphifyy pinned `==0.9.12`; the toolkit depends on its internals (documented in Task 5's graphify-internals.md)
- Any Python script calling `graphify.extract.extract()` keeps its `if __name__ == '__main__':` guard (Windows multiprocessing)
- Comment style: terse lowercase fragments, `->` not unicode arrows, no decorative comments, always brace control-flow bodies in PS/JS
- No test framework: verification is commands with expected output, run for real

---

### Task 1: Scaffold the repo

**Files:**
- Create: `C:\github\cipp-dev-tools\.gitignore`
- Create: `C:\github\cipp-dev-tools\README.md` (stub; full content in Task 5)

**Interfaces:**
- Produces: initialized git repo on branch `main` at `C:\github\cipp-dev-tools`; `.gitignore` covering `cipp/`, `graphify-out/`, `docker-compose.override.yml`, `__pycache__/`. All later tasks commit into this repo.

- [ ] **Step 1: Create the directory and init git**

Run:
```powershell
New-Item -ItemType Directory -Force C:\github\cipp-dev-tools | Out-Null
git -C C:\github\cipp-dev-tools init -b main
```
Expected: `Initialized empty Git repository in C:/github/cipp-dev-tools/.git/`

- [ ] **Step 2: Write `.gitignore`**

```
# the monorepo clone lives inside this workspace, never tracked here
cipp/
# graph outputs
graphify-out/
# personal docker tweaks
docker-compose.override.yml
__pycache__/
```

- [ ] **Step 3: Write stub `README.md`**

```markdown
# cipp-dev-tools

one-clone bootstrap for CIPP monorepo local dev. full docs land with setup tooling.
```

- [ ] **Step 4: Commit**

```powershell
git -C C:\github\cipp-dev-tools add .gitignore README.md
git -C C:\github\cipp-dev-tools commit -m "chore: scaffold workspace repo"
```
Expected: 1 commit on main, 2 files.

---

### Task 2: setup.ps1 + live bootstrap run

**Files:**
- Create: `C:\github\cipp-dev-tools\setup.ps1`

**Interfaces:**
- Consumes: gh CLI authenticated as k-grube; Task 1 repo
- Produces: `cipp\` = clone of the user's fork of CyberDrain/CIPP with `origin` = fork, `upstream` = CyberDrain/CIPP; graphifyy==0.9.12 importable. `-SkipGraph` switch (graph build deferred to Task 3, which creates the toolkit).

- [ ] **Step 1: Write `setup.ps1`**

```powershell
#Requires -Version 7
param([switch]$SkipGraph)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Assert-Tool($name, $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "missing prerequisite: $name -> $hint"
    }
}

Assert-Tool git 'https://git-scm.com'
Assert-Tool gh 'https://cli.github.com then: gh auth login'
Assert-Tool docker 'Docker Desktop: https://docker.com'
Assert-Tool wt 'Windows Terminal (upstream dev launcher requires it)'
Assert-Tool node 'https://nodejs.org'
Assert-Tool yarn 'npm install -g yarn'
Assert-Tool python 'https://python.org'

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'gh not authenticated -> gh auth login'
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'docker desktop not running'
}

$cipp = Join-Path $root 'cipp'
if (-not (Test-Path $cipp)) {
    # forks CyberDrain/CIPP under the authed user (reuses an existing fork), clones into cipp\
    Push-Location $root
    try {
        gh repo fork CyberDrain/CIPP --clone -- cipp
        if ($LASTEXITCODE -ne 0) {
            throw 'gh repo fork --clone failed'
        }
    } finally {
        Pop-Location
    }
}

# idempotent remote repair: origin = fork (left as gh set it), upstream = CyberDrain
Push-Location $cipp
try {
    if ((git remote) -notcontains 'upstream') {
        git remote add upstream https://github.com/CyberDrain/CIPP.git
    }
    git remote set-url upstream https://github.com/CyberDrain/CIPP.git
} finally {
    Pop-Location
}

python -c "import graphify" 2>$null
if ($LASTEXITCODE -ne 0) {
    pip install graphifyy==0.9.12
}
python -c "import importlib.metadata as m; v = m.version('graphifyy'); assert v == '0.9.12', v; print('graphifyy', v)"

if (-not $SkipGraph) {
    $rebuild = Join-Path $root 'graph-tools\rebuild-graph.ps1'
    if (Test-Path $rebuild) {
        & $rebuild
    } else {
        Write-Host 'graph-tools not present yet, skipping graph build'
    }
}
Write-Host 'setup complete'
```

- [ ] **Step 2: Run it (this creates the fork + clone for real)**

Run: `C:\github\cipp-dev-tools\setup.ps1 -SkipGraph`
Expected: prereq checks pass silently; fork created (or reused) and cloned into `C:\github\cipp-dev-tools\cipp`; `graphifyy 0.9.12` printed; `setup complete`. Takes a few minutes for the clone.

- [ ] **Step 3: Verify remotes and re-run idempotency**

Run:
```powershell
git -C C:\github\cipp-dev-tools\cipp remote -v
C:\github\cipp-dev-tools\setup.ps1 -SkipGraph
```
Expected: `origin` -> k-grube/CIPP fork of the monorepo (note: gh may name the fork `CIPP`; if k-grube/CIPP already exists as the OLD repo's fork, gh errors or reuses it - if the fork target resolves to the old KelvinTegelaar fork, STOP and report BLOCKED: the fork collision needs a human decision (rename old fork vs delete). Do not delete anything). `upstream` -> `https://github.com/CyberDrain/CIPP.git`. Second run completes fast with no re-clone and `setup complete`.

- [ ] **Step 4: Commit**

```powershell
git -C C:\github\cipp-dev-tools add setup.ps1
git -C C:\github\cipp-dev-tools commit -m "feat: bootstrap script (fork-aware clone, prereqs, pinned graphify)"
```

---

### Task 3: Port graph-tools + committed .graphifyignore + first monorepo graph build

**Files:**
- Create: `C:\github\cipp-dev-tools\graph-tools\common.py` (copied + edited)
- Create: `C:\github\cipp-dev-tools\graph-tools\routelink.py` (copied + edited)
- Create: `C:\github\cipp-dev-tools\graph-tools\rebuild.py` (copied, unchanged)
- Create: `C:\github\cipp-dev-tools\graph-tools\update.py` (copied, unchanged)
- Create: `C:\github\cipp-dev-tools\graph-tools\rebuild-graph.ps1` (copied, unchanged)
- Create: `C:\github\cipp-dev-tools\graph-tools\update-graph.ps1` (copied, unchanged)
- Create: `C:\github\cipp-dev-tools\.graphifyignore`

**Interfaces:**
- Consumes: `cipp\` clone from Task 2; source files at `C:\github\cipp-parent\graph-tools\`
- Produces: `graphify-out\graph.json` (directed monorepo graph), working `rebuild-graph.ps1` / `update-graph.ps1`. Node id prefixes become `cipp_frontend_*` / `cipp_backend_*`.

- [ ] **Step 1: Copy all six files**

```powershell
New-Item -ItemType Directory -Force C:\github\cipp-dev-tools\graph-tools | Out-Null
Copy-Item C:\github\cipp-parent\graph-tools\* C:\github\cipp-dev-tools\graph-tools\
```

- [ ] **Step 2: Edit `common.py` - repoint the stray-cache guard**

Old:
```python
    for repo in ('CIPP', 'CIPP-API'):
```
New:
```python
    for repo in ('cipp',):
```
(the scan root is now the workspace itself; the only possible stray scan-root cache is a direct scan of `cipp\`)

- [ ] **Step 3: Edit `routelink.py` - monorepo paths**

Old:
```python
    src = ROOT / 'CIPP' / 'src'
```
New:
```python
    src = ROOT / 'cipp' / 'frontend' / 'src'
```

Old:
```python
        if sf.startswith('CIPP/src') and label == Path(sf).name:
```
New:
```python
        if sf.startswith('cipp/frontend/src') and label == Path(sf).name:
```
(the `'CIPPHTTP' in sf` backend check needs no change; verify in step 5 that the monorepo layout still has `Modules/CIPPHTTP` under `cipp/backend/` - if the module moved, adjust that containment string to match reality and note it in the report)

- [ ] **Step 4: Write `.graphifyignore`**

First enumerate what actually exists:
```powershell
Get-ChildItem C:\github\cipp-dev-tools\cipp\backend\Modules -Directory | Select-Object -ExpandProperty Name
Get-ChildItem C:\github\cipp-dev-tools\cipp\backend\Tools -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
```

Then write `.graphifyignore` with root-anchored patterns: the structural set below verbatim, plus one `/cipp/backend/Modules/<name>` line per third-party module that exists (expected candidates: MicrosoftTeams, AzBobbyTables, PassPushPosh, HuduAPI, DNSHealth, AzureFunctions.PowerShell.Durable.SDK; first-party CIPP* modules stay in), plus `/cipp/backend/Tools/ModuleBuilder` if present:

```
# workspace tooling, not corpus
/graph-tools
/graphify-out
/docs
/.superpowers
# monorepo non-code
/cipp/build
/cipp/frontend/public
/cipp/github_assets
# vendored third-party modules
/cipp/backend/Modules/MicrosoftTeams
... (per enumeration)
```

`/cipp/build` excluded per spec lean (dev tooling, not app code).

- [ ] **Step 5: Detect sanity before building**

Run:
```powershell
python -c "
import json
from pathlib import Path
from collections import Counter
from graphify.detect import detect
r = detect(Path('C:/github/cipp-dev-tools'))
allf = sum(r['files'].values(), [])
top = Counter('/'.join(Path(f).parts[2:4]) for f in allf)
exts = Counter(Path(f).suffix.lower() for f in r['files']['code'])
print('total', r['total_files'], 'ps1', exts.get('.ps1', 0), 'jsx', exts.get('.jsx', 0) + exts.get('.js', 0))
print(dict(top.most_common(5)))
leak = [f for f in allf if any(s in f for s in ('MicrosoftTeams', '/build/', 'github_assets'))]
print('leaks', len(leak))
"
```
Expected: ps1 count in the ~2000s (backend), js/jsx in the ~1000s (frontend), leaks 0, only `cipp-dev-tools/cipp` paths. Also confirm `Modules/CIPPHTTP` exists under backend (for step 3's containment check). If counts are wildly off, fix `.graphifyignore` before proceeding.

- [ ] **Step 6: Full build**

Run: `C:\github\cipp-dev-tools\graph-tools\rebuild-graph.ps1` (from anywhere; wrappers Push-Location themselves). Cold AST build: expect several minutes, a zero-node-files warning (graphify #1666, benign), then route pass, then html export.

Note: the semantic cache is empty in this workspace, so `semantic: N docs uncached, skipped` is expected - the graph starts AST+routes only. Semantic-seed decision (spec open question): check whether `C:\github\cipp-parent\graphify-out\cache` entries hit against monorepo docs by comparing a couple of file hashes (the monorepo migration likely changed paths/content -> misses). If they'd miss, record "seed skipped, one-time /graphify session documented instead" in the report and CLAUDE.md stays as Task 5 writes it. Do not copy the old cache blindly.

- [ ] **Step 7: Verify the graph**

Run:
```powershell
python -c "
import json
from pathlib import Path
g = json.loads(Path('C:/github/cipp-dev-tools/graphify-out/graph.json').read_text(encoding='utf-8'))
edges = g.get('links', g.get('edges', []))
routes = [e for e in edges if e.get('source_file') == 'graph-tools/route-links']
teams = [n for n in g['nodes'] if 'MicrosoftTeams' in (n.get('source_file') or '')]
print('directed', g.get('directed'), 'nodes', len(g['nodes']), 'edges', len(edges), 'routes', len(routes), 'teams', len(teams))
"
```
Expected: `directed True`, nodes > 5000, routes in the hundreds (monorepo frontend still uses `/api/X`), teams 0. If routes == 0, debug routelink's path edits (step 3) against actual node source_file values before proceeding.

Then no-op update: `C:\github\cipp-dev-tools\graph-tools\update-graph.ps1` -> `up to date, nothing changed`, seconds.

- [ ] **Step 8: Commit**

```powershell
git -C C:\github\cipp-dev-tools add graph-tools .graphifyignore
git -C C:\github\cipp-dev-tools commit -m "feat: knowledge-graph toolkit ported to monorepo layout"
```

---

### Task 4: dev.ps1

**Files:**
- Create: `C:\github\cipp-dev-tools\dev.ps1`

**Interfaces:**
- Consumes: `cipp\build\tools\Start-Cipp-Dev-Windows-docker.ps1` (upstream), optional `docker-compose.override.yml` at repo root
- Produces: the daily launch command

- [ ] **Step 1: Write `dev.ps1`**

```powershell
#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$cipp = Join-Path $root 'cipp'
if (-not (Test-Path $cipp)) {
    throw 'cipp\ missing -> run setup.ps1 first'
}
$launcher = Join-Path $cipp 'build\tools\Start-Cipp-Dev-Windows-docker.ps1'
if (-not (Test-Path $launcher)) {
    throw "upstream launcher not found at $launcher (monorepo layout changed?)"
}
$override = Join-Path $root 'docker-compose.override.yml'
if (-not (Test-Path $override)) {
    & $launcher @args
    exit $LASTEXITCODE
}

# override mode: upstream invokes compose with explicit -f, which disables automatic
# docker-compose.override.yml merging, so chain the files ourselves for the docker tab
# and reuse upstream's module-watcher + frontend tabs verbatim
Write-Warning 'override mode: bypassing upstream launcher for the docker tab (drift risk if upstream changes its compose flow)'
Get-Command wt -ErrorAction Stop | Out-Null
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
$frontendPath = Join-Path $cipp 'frontend'
$dockerPath = Join-Path $cipp 'build'
$frontendCommand = 'try { yarn install --network-timeout 500000; yarn run dev } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$dockerCommand = "try { ./tools/build-dev-modules.ps1; docker compose -f docker-compose-no-frontend.yml -f `"$override`" up --pull always --watch } catch { Write-Error `$_.Exception.Message } finally { Read-Host 'Press Enter to exit' }"
$watcherCommand = 'try { ./tools/Watch-Cipp-Dev-Modules.ps1 -SkipInitialBuild } catch { Write-Error $_.Exception.Message } finally { Read-Host "Press Enter to exit" }'
$enc = { param($s) [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s)) }
docker volume create cipp-ng_azurite-data | Out-Null
wt --title CIPP-Docker -d $dockerPath pwsh -EncodedCommand (& $enc $dockerCommand)`; new-tab --title 'CIPP Modules' -d $dockerPath pwsh -EncodedCommand (& $enc $watcherCommand)`; new-tab --title 'CIPP Frontend' -d $frontendPath pwsh -EncodedCommand (& $enc $frontendCommand)
Write-Host "`n  API + Frontend: http://localhost:5196" -ForegroundColor Green
```

- [ ] **Step 2: Verify without launching the full stack**

Run:
```powershell
pwsh -NoProfile -Command "& { `$t = [System.Management.Automation.Language.Parser]::ParseFile('C:\github\cipp-dev-tools\dev.ps1', [ref]`$null, [ref]`$e = `$null); if (`$e) { `$e } else { 'parse ok' } }"
Test-Path C:\github\cipp-dev-tools\cipp\build\tools\Start-Cipp-Dev-Windows-docker.ps1
Test-Path C:\github\cipp-dev-tools\cipp\build\docker-compose-no-frontend.yml
```
Expected: `parse ok`, `True`, `True`. Do NOT launch the environment (opens terminal tabs, pulls containers); full launch is a documented manual step for the user. If the parse-check one-liner fights quoting, an acceptable substitute is `pwsh -NoProfile -Command "Get-Command -Syntax C:\github\cipp-dev-tools\dev.ps1"` erroring cleanly or any equivalent syntax-only validation - state which was used.

- [ ] **Step 3: Commit**

```powershell
git -C C:\github\cipp-dev-tools add dev.ps1
git -C C:\github\cipp-dev-tools commit -m "feat: dev launcher wrapping upstream stack with compose override hook"
```

---

### Task 5: Docs, CLAUDE.md, README, publish

**Files:**
- Create: `C:\github\cipp-dev-tools\CLAUDE.md`
- Create: `C:\github\cipp-dev-tools\README.md` (replace stub)
- Create: `C:\github\cipp-dev-tools\docs\graphify-internals.md`
- Copy: spec + this plan from `C:\github\cipp-parent\docs\superpowers\{specs,plans}\2026-07-21-*.md` into `C:\github\cipp-dev-tools\docs\`

**Interfaces:**
- Consumes: everything prior; upstream contribution docs for the PR-target-branch fact
- Produces: published k-grube/cipp-dev-tools

- [ ] **Step 1: Determine the PR target branch**

Run: `gh api repos/CyberDrain/CIPP/branches --jq '.[].name'` and `gh api repos/CyberDrain/CIPP --jq '.default_branch'`
Record the answer (expect `main` default; if a `dev` branch exists, check upstream CONTRIBUTING/docs.cipp.app dev guide for which one PRs target). Use the finding in CLAUDE.md.

- [ ] **Step 2: Write `CLAUDE.md`**

```markdown
# cipp-dev-tools workspace

bootstrap workspace for CIPP monorepo dev. `cipp\` is the monorepo clone (origin = your fork, upstream = CyberDrain/CIPP), gitignored here.

## dev environment

- `dev.ps1` launches the full local stack (azurite + CRAFT api container + module watcher + yarn frontend), everything at http://localhost:5196
- personal tweaks: drop a gitignored `docker-compose.override.yml` at this root, dev.ps1 chains it (upstream's own launcher would ignore it, explicit -f disables auto-merge)
- `setup.ps1` is idempotent, re-run to repair prereqs/remotes

## knowledge graph

`graphify-out\graph.json` is a directed graph of the monorepo (AST + `http_calls` edges linking frontend `/api/X` calls to backend `Invoke-X` functions). check it before grepping. `graphify-out\GRAPH_REPORT.md` has the community map, `route-orphans.json` the unresolved routes.

- after code changes: `graph-tools\update-graph.ps1` (~10s, no LLM). `--cluster` re-clusters + regenerates the report
- full rebuild: `graph-tools\rebuild-graph.ps1` (needed when update refuses with the shrink-guard error, or after `.graphifyignore` changes)
- doc/image changes are not picked up by these scripts, a /graphify session adds semantic content (one-time after a fresh clone too)

## rules

- never run the /graphify skill or `graphify extract` against `cipp\` directly, work from this root, outputs stay here
- detect scope: `.graphifyignore` at this root (committed, root-anchored, graphify's fnmatch `*` crosses `/`). new vendored modules under `cipp\backend\Modules\` need an entry
- route edges carry synthetic `source_file` `graph-tools/route-links` (real path in `source_location`), never retag with real paths (build_merge replace-on-re-extract would wipe those files' AST nodes)
- graphifyy is pinned ==0.9.12, `docs\graphify-internals.md` lists the internals the toolkit depends on, re-verify before any bump
- contributions: branch on the fork, PR to CyberDrain/CIPP <TARGET_BRANCH from step 1>. commit in `cipp\` only when the user asks, suggest message and stop
```

(replace `<TARGET_BRANCH from step 1>` with the actual finding)

- [ ] **Step 3: Write `docs\graphify-internals.md`**

```markdown
# graphify 0.9.12 internals the toolkit depends on

pin is exact (`graphifyy==0.9.12`). before bumping, re-verify each:

- ignore matching uses python fnmatch: `*` crosses `/`. root-anchored patterns (leading `/`) fnmatch against the scan-root-relative path as a full string; unanchored patterns match every path component at every depth (why all our entries are anchored)
- nested `.gitignore` / `.graphifyignore` inside subdirectories are NOT read when scanning from a parent root (`_load_graphifyignore` walks upward only). our committed `.graphifyignore` is the single scope authority
- `build_merge` does NOT persist to disk (docstring claims otherwise). every caller must to_json afterward
- `build_merge` replace-on-re-extract: all base-graph nodes/edges whose `source_file` matches any incoming one are dropped before merge. this is why route edges use the synthetic `graph-tools/route-links` source
- `to_json(G, communities, path, force=, community_labels=)` returns False (writing nothing) when the new graph has fewer nodes than the existing file unless force=True (#479). update.py wraps this with its own 10 percent threshold + force=True; routelink/recluster use force=False deliberately
- `python -m graphify export html` reads community groupings from `.graphify_analysis.json` and labels from `.graphify_labels.json` - both must be regenerated whenever clustering changes (rebuild.py and update.py --cluster do)
- `graphify.extract.extract` uses multiprocessing: any calling script needs `if __name__ == '__main__':` on windows
- detect writes `graphify-out/cache/stat-index.json` into the scan root
- zero-node source files are reported and retried each run (#1666), the warning is benign
```

- [ ] **Step 4: Write full `README.md`**

```markdown
# cipp-dev-tools

one-clone bootstrap for [CIPP](https://github.com/CyberDrain/CIPP) monorepo local development, with a code knowledge graph for AI-assisted work.

## quick start

​```powershell
git clone https://github.com/k-grube/cipp-dev-tools
cd cipp-dev-tools
.\setup.ps1     # forks + clones CyberDrain/CIPP into cipp\, installs pinned graphify, builds the graph
.\dev.ps1       # launches the local dev stack -> http://localhost:5196
​```

prereqs: git, gh (authed), Docker Desktop, Windows Terminal, node + yarn, python 3.

## what you get

- `cipp\` - monorepo clone, origin = your fork, upstream = CyberDrain (PR-ready)
- local dev stack via upstream's own `build\` tooling (azurite, CRAFT api container, module watcher, frontend dev server)
- `graphify-out\graph.json` - directed knowledge graph of frontend + backend incl. `http_calls` edges mapping `/api/X` calls to `Invoke-X` functions
- `CLAUDE.md` so Claude Code sessions know all of the above

## daily commands

| command | what |
|---|---|
| `dev.ps1` | launch the dev environment |
| `graph-tools\update-graph.ps1` | refresh the graph after code changes (~10s) |
| `graph-tools\update-graph.ps1 --cluster` | + re-cluster and regenerate GRAPH_REPORT.md |
| `graph-tools\rebuild-graph.ps1` | full graph rebuild |

personal docker tweaks: drop a `docker-compose.override.yml` at the repo root (gitignored), `dev.ps1` picks it up.

## notes

- `graphifyy` is pinned to 0.9.12 on purpose - `docs\graphify-internals.md` explains what must be re-verified before bumping
- fresh clones build an AST+routes graph; doc-derived semantic content needs a one-time `/graphify` session in Claude Code
​```
```
(strip the zero-width escapes around the inner code fences when writing the real file)

- [ ] **Step 5: Copy design docs**

```powershell
New-Item -ItemType Directory -Force C:\github\cipp-dev-tools\docs | Out-Null
Copy-Item C:\github\cipp-parent\docs\superpowers\specs\2026-07-21-cipp-dev-tools-design.md C:\github\cipp-dev-tools\docs\
Copy-Item C:\github\cipp-parent\docs\superpowers\plans\2026-07-21-cipp-dev-tools.md C:\github\cipp-dev-tools\docs\
```

- [ ] **Step 6: Verify every command in CLAUDE.md/README exists**

Run: `Test-Path` on `setup.ps1`, `dev.ps1`, `graph-tools\update-graph.ps1`, `graph-tools\rebuild-graph.ps1`, `docs\graphify-internals.md` from the repo root - all True. Re-run `graph-tools\update-graph.ps1` once more -> `up to date, nothing changed`.

- [ ] **Step 7: Commit and publish**

```powershell
git -C C:\github\cipp-dev-tools add CLAUDE.md README.md docs
git -C C:\github\cipp-dev-tools commit -m "docs: agent context, readme, graphify internals, design docs"
gh repo create k-grube/cipp-dev-tools --public --source C:\github\cipp-dev-tools --push
```
Expected: repo created, main pushed. (User authorized this publish when commissioning the repo; if `gh repo create` reports the name already exists, STOP and ask rather than force-pushing.)

---

## Self-Review Notes

- Spec coverage: layout (T1), setup/fork/pin (T2), graph port + committed ignore + open questions vendored-list/cipp-build/semantic-seed/CIPPHTTP-path (T3), dev wrapper + override deviation (T4), CLAUDE.md/README/internals-doc/PR-branch question/publish (T5). Migration section needs no task (cipp-parent untouched by design).
- Fork-collision risk (k-grube/CIPP already forks the OLD repo) is a named BLOCKED condition in T2, not silently improvised.
- dev.ps1 override-mode wt/base64 replication mirrors upstream's launcher observed 2026-07-21; if upstream's script has changed by execution time, the implementer should mirror the current version and note the delta.
- No git operations inside cipp\ anywhere except remote add/set-url (T2), which is config, not history.
