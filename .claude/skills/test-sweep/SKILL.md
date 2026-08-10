---
name: test-sweep
description: Multi-agent sweep that adds missing frontend tests pinning real failure modes. Trigger - /test-sweep backfill (crawl the whole frontend off a ranked backlog) or /test-sweep sync [range] (pin behavior changed by an upstream sync). Also when the user asks to backfill tests, cover upstream changes with tests, or resume the sweep.
---

# test-sweep

multi-agent frontend test sweep. pipeline per run: scout -> write (fan-out) -> verify (default-deny) -> gate -> session-side state updates. run size: top 10-12 pending backlog entries. design rationale in `docs/superpowers/specs/2026-08-01-test-sweep-design.md` (local-only, this repo is public; the skill is self-contained without it).

## value bar

single source: `.claude/skills/component-tests/policy.md` (hard rules, forbidden list, jsdom-vs-storybook placement). read it and inject its rules sections, not the title/preamble, as `{{POLICY}}` (anchor in run pipeline below). never restate it here, two copies drift.

## state

state lives under `docs/` because this repo is public and both files describe un-fixed CIPP bugs. gitignored, never committed, create on first run.

- `docs/test-sweep/backlog.json`: array of `{file, failureMode, evidence, score, mode, status}`; status `pending | written | rejected | red-pin`. scout refreshes scores and appends, never erases statuses. entries flipped to `red-pin` also record `testPath` and the red test names (the gate's accumulated expected-red list rebuilds from these). missing -> create as `[]` and let the scout fill it, that's a cold start not an error.
- `docs/test-sweep/last-sync.txt`: dev commit of the last gated sync sweep. advance only after the gate passes. missing -> sync mode needs an explicit range argument, never diff all of dev.

## mode: backfill

scout = 3 parallel agents, merge scores in-session, refresh backlog:

1. coverage agent: run `.\test.ps1 --coverage` from the workspace root (macos: `./test.sh --coverage`), or read the last coverage output if fresh; list frontend source files with 0 or trivial coverage
2. graph agent: `python graph-tools\query.py find <candidates>` fan-in ranking; high fan-in first (shared components, formatters, table utils)
3. pattern/churn agent: grep frontend src for crash-prone patterns (unguarded `Object.keys(`, `.map(` on api-shaped props, `.label ??`-less member access in formatter branches) + `git -C CIPP log --since=90.days --name-only` churn counts + `docs/upstream-findings.md` mentions (local-only, skip that input if absent)

score = fan-in x (has crash-pattern or findings mention) x churn, zero coverage required. every entry needs a concrete `failureMode` hypothesis; no hypothesis -> not a target.

## mode: sync

- range: argument if given, else `$(Get-Content docs/test-sweep/last-sync.txt)..dev`; no argument and no marker -> ask for a range, don't fall back to the whole branch
- `git -C CIPP diff <range> -- frontend/src` -> keep behavior-bearing hunks (logic, formatting, data flow); skip pure styling/copy
- hypothesis comes from the hunk itself ("null guard added at X, pin the null path")
- sync entries get `mode: "sync"` and outrank backfill entries in assignment order

## run pipeline

1. scout per mode above, update `backlog.json`
2. take top 10-12 `pending` (sync first, then score), build assignments: `{file, failureMode, evidence, testPath, project}` where `testPath` mirrors existing layout (`CIPP/frontend/tests/components/...` / `tests/pages/...`) and `project` is `unit` or `storybook` per the placement rule in `.claude/skills/component-tests/policy.md`
3. read `writer-prompt.md`, `verifier-prompt.md`, `gate-prompt.md` from this skill dir; expand `{{POLICY}}` in writer-prompt.md with `.claude/skills/component-tests/policy.md`'s contents from the `## hard rules` heading onward (drop the title and preamble, those are maintainer-facing, not writer-facing) before passing it; launch Workflow with `scriptPath: .claude/skills/test-sweep/workflow.js` and `args: {assignments, writerPrompt, verifierPrompt, gatePrompt, priorRedPins}` where `priorRedPins` = `[{file, name}]` rebuilt from backlog entries with status red-pin
4. session-side after the workflow returns: append findings entries for `red-pin` results to `docs/upstream-findings.md` (continue existing numbering; create the file if this is a cold start), update backlog statuses, advance `last-sync.txt` (sync mode, gate green), commit test files with a `test:` commit (backlog/findings/marker are local-only under docs\, never committed); any NEW test the gate flags as an unexpected failure is pulled and logged in the report, report per `routing` below

## routing / report

- green confirmed test -> ships
- red pin (verifier confirmed the bug is reachable via a shipped producer) -> stays red + findings entry
- red but producer unreachable -> test deleted, findings note only
- rejected by verifier -> deleted, reason in report
- gate-flagged unexpected failure in a new test -> test pulled, logged in report
- report: tests added grouped by failure mode, red pins with findings numbers, rejections with reasons, backlog burn-down, suite runtime delta vs the ~77s baseline. if the suite trends past ~2x, tighten the value bar, don't split the suite.

## out of scope

fixing found bugs (separate branches per cipp-dev-workflow), backend Pester, live-stack e2e, deleting or rewriting tests that predate the run.
