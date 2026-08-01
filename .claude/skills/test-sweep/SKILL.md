---
name: test-sweep
description: Multi-agent sweep that adds missing frontend tests pinning real failure modes. Trigger - /test-sweep backfill (crawl the whole frontend off a ranked backlog) or /test-sweep sync [range] (pin behavior changed by an upstream sync). Also when the user asks to backfill tests, cover upstream changes with tests, or resume the sweep.
---

# test-sweep

multi-agent frontend test sweep. spec: `docs/superpowers/specs/2026-08-01-test-sweep-design.md`. pipeline per run: scout -> write (fan-out) -> verify (default-deny) -> gate -> session-side state updates. run size: top 10-12 pending backlog entries.

## hard rules (inject into every writer prompt)

- every `it()` pins a named failure mode: the test fails if that specific bug is (re)introduced, and the name says what breaks ("preset filters queued rows", not "renders table")
- forbidden: render-smoke tests, snapshots, MUI-internal assertions, style assertions, synthetic producer rows (find the shipped producer or drop the target), per-call waitFor timeouts
- fixtures match the real producer shape: read the backend ps1 / Craft C# / graph producer before writing the fixture. `spec/cipp-openapi-v2.json` helps, code is authoritative
- nothing that needs the live dev stack
- read `docs/toolchain-notes.md` before writing (jsdom/MRT/coverage traps), and `frontend-tests/tests/test-utils.jsx` for providers
- follow repo comment/style conventions: terse lowercase comments, no decorative markers, ASCII ->, braces on all control flow

## jsdom vs storybook

quoted from CIPP `d21bf34d6:docs/dev-documentation/cipp-dev-guide/frontend-testing.md` (feat/frontend-tests branch; re-point to the merged doc once upstream merges the tests PR):

> - If you are asserting render branches, prop handling, text output, or utility functions, write a `.test.jsx` file in jsdom. These are fast, need no browser, and heavy child components can be mocked with `vi.mock`.
> - If the component needs real layout, scrolling, portals, or browser APIs that jsdom can't fake (the Material React Table row virtualizer, drag interactions), write a story with a `play()` function that asserts the behavior. The storybook project runs every story in Chromium.
> - A story that is purely visual documentation is fine too, it still counts as a render smoke test. It will catch a crash, but nothing subtler.
> - Prefer asserting output and behavior over presence. A dependency bump that changes *what* renders (not *whether* it renders) should fail a test.

default jsdom. a purely-visual story never satisfies the value bar on its own.

## state

- `docs/test-sweep/backlog.json`: array of `{file, failureMode, evidence, score, mode, status}`; status `pending | written | rejected | red-pin`. scout refreshes scores and appends, never erases statuses. entries flipped to `red-pin` also record `testPath` and the red test names (the gate's accumulated expected-red list rebuilds from these).
- `docs/test-sweep/last-sync.txt`: dev commit of the last gated sync sweep. advance only after the gate passes.

## mode: backfill

scout = 3 parallel agents, merge scores in-session, refresh backlog:

1. coverage agent: run `.\test.ps1 --coverage` (or read the last coverage output if fresh), list frontend source files with 0 or trivial coverage
2. graph agent: `python graph-tools\query.py find <candidates>` fan-in ranking; high fan-in first (shared components, formatters, table utils)
3. pattern/churn agent: grep frontend src for crash-prone patterns (unguarded `Object.keys(`, `.map(` on api-shaped props, `.label ??`-less member access in formatter branches) + `git -C CIPP log --since=90.days --name-only` churn counts + `docs/upstream-findings.md` mentions

score = fan-in x (has crash-pattern or findings mention) x churn, zero coverage required. every entry needs a concrete `failureMode` hypothesis; no hypothesis -> not a target.

## mode: sync

- range: argument if given, else `$(Get-Content docs/test-sweep/last-sync.txt)..dev`
- `git -C CIPP diff <range> -- frontend/src` -> keep behavior-bearing hunks (logic, formatting, data flow); skip pure styling/copy
- hypothesis comes from the hunk itself ("null guard added at X, pin the null path")
- sync entries get `mode: "sync"` and outrank backfill entries in assignment order

## run pipeline

1. scout per mode above, update `backlog.json`
2. take top 10-12 `pending` (sync first, then score), build assignments: `{file, failureMode, evidence, testPath, project}` where `testPath` mirrors existing layout (`frontend-tests/tests/components/...` / `tests/pages/...`) and `project` is `unit` or `storybook` per the placement rule
3. read `writer-prompt.md`, `verifier-prompt.md`, `gate-prompt.md` from this skill dir; expand `{{POLICY}}` in writer-prompt.md with the "hard rules" and "jsdom vs storybook" sections of this skill before passing it; launch Workflow with `scriptPath: .claude/skills/test-sweep/workflow.js` and `args: {assignments, writerPrompt, verifierPrompt, gatePrompt, priorRedPins}` where `priorRedPins` = `[{file, name}]` rebuilt from backlog entries with status red-pin
4. session-side after the workflow returns: append findings entries for `red-pin` results (continue existing numbering), update backlog statuses, advance `last-sync.txt` (sync mode, gate green), commit test files with a `test:` commit (backlog/findings/marker are local-only under docs\, never committed); any NEW test the gate flags as an unexpected failure is pulled and logged in the report, report per `routing` below

## routing / report

- green confirmed test -> ships
- red pin (verifier confirmed the bug is reachable via a shipped producer) -> stays red + findings entry
- red but producer unreachable -> test deleted, findings note only
- rejected by verifier -> deleted, reason in report
- gate-flagged unexpected failure in a new test -> test pulled, logged in report
- report: tests added grouped by failure mode, red pins with findings numbers, rejections with reasons, backlog burn-down, suite runtime delta vs the ~77s baseline. if the suite trends past ~2x, tighten the value bar, don't split the suite.

## out of scope

fixing found bugs (separate branches per cipp-dev-workflow), backend Pester, live-stack e2e, deleting or rewriting tests that predate the run.
