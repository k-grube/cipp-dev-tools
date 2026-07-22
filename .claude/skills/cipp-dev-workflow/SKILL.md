---
name: cipp-dev-workflow
description: Use when working a CIPP GitHub issue, branching, syncing the fork, checking fork drift, or opening a PR to upstream from the cipp\ monorepo clone in this workspace. Triggers - "tackle this CIPP issue", "start work on issue #X", "sync the fork", "open a PR for CIPP", any git branch/PR work inside cipp\.
---

# CIPP Contribution Workflow

How contributions flow from your fork of the CIPP monorepo to CyberDrain upstream, from picking up a GitHub issue to landing the fix. Frontend and backend live in one repo now (`cipp\frontend\`, `cipp\backend\`), one branch and one PR covers both.

## Repo layout

`cipp\` under this workspace root is the monorepo clone (gitignored here, its own git history):

| Remote | Points to | Purpose |
|---|---|---|
| `origin` | your fork of CyberDrain/CIPP (user or org, whatever setup cloned) | branches push here |
| `upstream` | `CyberDrain/CIPP` | the real project, PRs land here |

**PRs go to `upstream/dev`, never `main`** (`main` is release-only). This overrides any generic "PR to main" instinct.

**Never run `git commit` or `git push` in `cipp\` unless the user explicitly asks.** Prepare the changes, suggest a commit message, stop. Same for squash and force-push steps below: print the commands and message, let the user run them.

## Before grepping: the knowledge graph

`graphify-out\graph.json` (workspace root) maps the whole monorepo, incl. `http_calls` edges linking frontend `/api/X` calls to backend `Invoke-X` functions. Query it first. After code changes run `graph-tools\update-graph.ps1` (~10s) so the graph stays current.

## The workflow

### 1. Check fork drift before starting anything new

```
git fetch origin upstream
git log --oneline origin/dev..upstream/dev | wc -l   # commits origin is missing
git log --oneline upstream/dev..origin/dev | wc -l   # should be ~0
```

If `origin/dev` is behind, sync before branching (fast-forward merge of `upstream/dev`, then push to `origin/dev`), otherwise the eventual PR carries unrelated catch-up commits. Report the drift count and confirm before any push to `origin/dev`.

### 2. Confirm the dev stack is healthy

From the workspace root (not `cipp\`): `dev.ps1` launches the full stack (azurite + Craft api container + module watcher + yarn frontend), everything at http://localhost:5196. `stop.ps1` tears it down. The module watcher rebuilds backend modules on save and the frontend hot-reloads, no manual container rebuild for normal code changes. Don't trust test results against a half-started stack.

### 3. Branch off `dev`

```
git checkout dev && git pull origin dev
git checkout -b fix/<short-name>     # or feat/
```

Name for what it does, not the issue number (`fix/mailbox-search-timeout`, not `fix/issue-482`).

### 4. Implement

Edit freely, run `graph-tools\update-graph.ps1` after changes. When a checkpoint is worth committing, suggest a conventional message (`fix:`, `feat:`, `test:`) and let the user commit. Granularity doesn't matter yet, everything squashes in step 6.

### 5. Test

- frontend: exercise the UI against the local stack, `yarn lint` in `cipp\frontend\`
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

Then open the PR: `fix/<short-name>` -> `CyberDrain/CIPP` `dev`. Once it merges and `origin/dev` syncs back down (step 1's drift check), the branch is fully merged and can be deleted.

## Notes

- Out-of-scope bugs or missing coverage spotted mid-issue: file a GitHub issue on CyberDrain/CIPP, don't fold them in.
- "Check fork drift" alone means step 1 only, report the numbers, don't start branching.
- `spec\cipp-openapi-v2.json` (workspace root) has request/response shapes for ~80% of endpoints; the graph and code are authoritative when they disagree.
