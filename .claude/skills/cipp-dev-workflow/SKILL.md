---
name: cipp-dev-workflow
description: Use when working a CIPP GitHub issue, branching, syncing the fork, checking fork drift, or opening a PR to upstream from the CIPP\ monorepo clone in this workspace. Triggers - "tackle this CIPP issue", "start work on issue #X", "sync the fork", "open a PR for CIPP", any git branch/PR work inside CIPP\.
---

# CIPP Contribution Workflow

How contributions flow from your fork of the CIPP monorepo to CyberDrain upstream, from picking up a GitHub issue to landing the fix. Frontend and backend live in one repo now (`CIPP\frontend\`, `CIPP\backend\`), one branch and one PR covers both.

## Repo layout

`CIPP\` under this workspace root is the monorepo clone (gitignored here, its own git history):

| Remote | Points to | Purpose |
|---|---|---|
| `origin` | your fork of CyberDrain/CIPP (user or org, whatever setup cloned) | branches push here |
| `upstream` | `CyberDrain/CIPP` | the real project, PRs land here |

**PRs go to `upstream/dev`, never `main`** (`main` is release-only). This overrides any generic "PR to main" instinct.

**Never run `git commit`, `git push`, or `gh pr create` against `CIPP\`/upstream unless the user explicitly asks.** Prepare the changes, suggest the commands and message/PR body, stop. Same for squash, force-push, and branch-delete steps below: print the commands, let the user run them.

## Before grepping: the knowledge graph

`graphify-out\graph.json` (workspace root) maps the monorepo + craft runtime: `http_calls` edges (frontend `/api/X` -> backend `Invoke-X`, frontend -> craft auth/setup routes), `bridge_calls` edges (backend -> craft C# bridges), `external_api` nodes (microsoft endpoints), plus semantic doc/concept nodes. Query it with `python graph-tools\query.py` (`find` / `node` / `path` / `trace <ApiEndpointName>`, macos `.venv/bin/python`), don't hand-roll graph.json scripts; `trace` prints the frontend -> backend -> craft -> microsoft chain.

Keeping it current (graph.json + sidecars + `cache\semantic\` are committed in this repo, commit the refreshed files after any of these):

- code changes (yours or upstream sync): `graph-tools\update-graph.ps1` (~10s, no LLM). run it with `dev` checked out in `CIPP\` (switch back after), the committed graph tracks dev, never feature-branch state
- doc changes: run a `/graphify . --update` session (only changed docs re-extract, content-hash cache), then `graph-tools\rebuild-graph.ps1` to merge
- shrink-guard refusal, `.graphifyignore` change, or doc deletions: `graph-tools\rebuild-graph.ps1`

## The workflow

### 1. Check fork drift before starting anything new

```
git fetch --multiple origin upstream
git log --oneline origin/dev..upstream/dev | wc -l   # commits origin is missing
git log --oneline upstream/dev..origin/dev | wc -l   # should be ~0
```

If `origin/dev` is behind, sync before branching (fast-forward merge of `upstream/dev`, then push to `origin/dev`), otherwise the eventual PR carries unrelated catch-up commits. Report the drift count and confirm before any push to `origin/dev`.

### 2. Confirm the dev stack is healthy

From the workspace root (not `CIPP\`): `dev.ps1` launches the full stack (azurite + Craft api container + module watcher + yarn frontend), everything at http://localhost:5196. `stop.ps1` tears it down. The module watcher rebuilds backend modules on save and the frontend hot-reloads, no manual container rebuild for normal code changes. Don't trust test results against a half-started stack.

### 3. Branch off `dev`

```
git checkout dev && git pull origin dev
git checkout -b fix/<short-name>     # or feat/
```

Name for what it does, not the issue number (`fix/mailbox-search-timeout`, not `fix/issue-482`).

### 4. Implement

Edit freely, run `graph-tools\update-graph.ps1` after changes. When a checkpoint is worth committing, suggest a conventional message (`fix:`, `feat:`, `test:`) and let the user commit. Granularity doesn't matter yet, everything squashes in step 6.

### 5. Test

- frontend: **vitest coverage is expected for changed or added components.** Invoke `/component-tests` *before* writing any, not after. It carries the value bar (`policy.md`), the survey that finds what is already pinned (including tests living in a parent's file), the jsdom vs story `play()` placement rule, and the red-for-the-right-reason / mutation-verify steps. Skipping it produces presence-only assertions that pin nothing, which is the failure mode that skill exists to stop. Suite lives at `frontend\tests\`. After the tests exist, run `yarn test` from `CIPP\frontend\` (both projects; needs `npx playwright install chromium` once), plus `yarn lint` and exercising the UI against the local stack. Conventions in `frontend/tests/Overview.mdx` + `docs/dev-documentation/cipp-dev-guide/frontend-testing.md`, gotchas in `spec\toolchain-notes.md` (workspace root). Bulk coverage backfill across the frontend is a different job: `/test-sweep`, not this workflow.
- backend: **Pester coverage is mandatory for any changed or added PowerShell function.** Tests live in `backend\Tests\` mirroring the module path (`Modules/CIPPCore/Public/Get-CIPPDrift.ps1` -> `Tests/Reports/Get-CIPPDrift.Tests.ps1`). Run via the repo runner:

```
pwsh backend\Tests\Invoke-CippTests.ps1 -Path backend\Tests\<area>\<Name>.Tests.ps1
```

Cover: the bug written to fail against old code, edge cases (null/empty, loops, cross-type comparisons), and adjacent behavior when the fix generalizes a comparison or filter. Check regressions in shared components (tables, standards, tenant selectors), a change in one place quietly breaks another page.

**Pester v5 gotcha:** code directly in a `Describe`/`Context` body runs only during Discovery and is gone by Run time, so helper `function`s defined there are unresolvable when a lazy `Mock -MockWith` fires (`CommandNotFoundException`). Define helpers inside `BeforeAll`.

### 6. Squash, push, PR

Suggest to the user:

```
git reset --soft dev
git commit                            # one message with full what/why detail
git push origin fix/<short-name>      # --force-with-lease if already pushed
```

Then suggest the PR command (`fix/<short-name>` -> `CyberDrain/CIPP` `dev`) with a drafted title + body, and stop. **Never run `gh pr create` against upstream yourself**, the user opens the PR (they can override by explicitly asking you to run it). Once it merges and `origin/dev` syncs back down (step 1's drift check), sweep branches (step 7).

### 7. Delete merged branches

Whenever step 1 runs (or the user asks for cleanup), check for branches whose PR already landed:

```
gh pr list --repo CyberDrain/CIPP --author @me --state merged --limit 30 --json headRefName -q '.[].headRefName'
```

Cross-check against `git branch` and `git branch -r`. PR state is the authority, `git branch --merged` misses squash-merged branches. For each merged branch still present:

```
git branch -D <branch>
git push origin --delete <branch>
```

Never delete: branches with an open PR, parked work (check memory + `docs\upstream-findings.md` if present, local-only), never-PR'd experiment branches, anything not yours (`KelvinTegelaar-patch-1`). The `push --delete` falls under the explicit-ask rule above: list what qualifies and let the user say go.

## Notes

- Out-of-scope bugs or missing coverage spotted mid-issue: file a GitHub issue on CyberDrain/CIPP, don't fold them in.
- "Check fork drift" alone means step 1 only, report the numbers, don't start branching.
- `spec\cipp-openapi-v2.json` (workspace root) has request/response shapes for ~80% of endpoints; the graph and code are authoritative when they disagree.
