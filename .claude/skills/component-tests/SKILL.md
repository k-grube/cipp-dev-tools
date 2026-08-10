---
name: component-tests
description: Interactive per-component frontend test writing for CIPP. Trigger - /component-tests [path], or when working on a component and asking what tests already exist, whether new tests are needed, or to TDD a fix. Bulk backfill across the frontend is /test-sweep, not this.
---

# component-tests

tests for the one component you are working on, in-session, no agents. value bar is `policy.md` next to this file, read it before writing anything.

`/component-tests [path]` where path is the component source relative to `CIPP\`. no arg -> infer from `git -C CIPP status --short -- frontend/src`; more than one changed component -> list them and ask which.

## 1. survey

- path mirror: `frontend/src/**` -> `frontend/tests/**`, e.g. `frontend/src/components/X/Y.jsx` -> `frontend/tests/components/X/Y.test.jsx` and `Y.stories.jsx`. covers `components`, `hooks`, `layouts`, `pages`, `theme`, `utils`. for `pages` the mirror isn't literal: source is often kebab-case (`src/pages/api-offline.js`), but the test is named for the exported PascalCase component (`tests/pages/ApiOfflinePage.test.jsx`). grep both names
- also grep `CIPP/frontend/tests` for the component name, tests for it can live in a parent's file
- read the `it()` names AND their assertions, not just the names. a name describing rendering rather than a failure mode usually asserts presence only, which pins nothing

report which failure modes are already pinned, and which existing tests pin nothing, before proposing anything.

## 2. propose gaps

each candidate needs a named failure mode not already pinned by the survey. no nameable failure mode -> not a test, say so and drop it.

present the list, let the user pick. writing the whole list unasked is the bloat this skill exists to prevent.

## 3. route

jsdom vs storybook per the placement rule in `policy.md`. jsdom default; story + `play()` only when the assertion needs real layout, scroll, portals, or the MRT virtualizer.

## 4. write and prove

run a single file with `npx vitest run --project <unit|storybook> <testPath>` from `CIPP\frontend`. pick which branch below by whether a source change is in flight.

**in-flight change** (bug fix or new behavior), tdd:

1. write the test first, run it, confirm red
2. confirm red for the named reason, not an import error, a bad fixture, or a missing provider. red for the wrong reason is not a red step
3. make the change, rerun, green

**existing behavior** (component unchanged, test green on first run), mutation-verify:

1. write the test, run it, confirm green
2. introduce the named failure in the component with a single Edit. record the original string verbatim before editing, so the revert in step 3 restores it exactly
3. rerun. either way revert with the inverse Edit immediately, then confirm `git -C CIPP diff --stat -- <file>` is empty (clean file), or matches the captured baseline (file with pre-existing edits), before moving on
4. still red after the mutation -> the test pins the failure, keep it. still green -> it proves nothing, delete it and say why

the mutation touches the user's working tree. never leave it, never commit it. a file carrying unrelated uncommitted edits -> say so and get an ok before mutating it, and capture `git -C CIPP diff -- <file>` before mutating so you have something other than empty to compare the post-revert diff against.

## 5. bug found, not fixing now

discard the test, never commit it red. then, in the workspace-root `docs/` (gitignored, never inside `CIPP\`):

- append `docs/upstream-findings.md` (existing numbering, create on cold start)
- append `docs/test-sweep/backlog.json`: `{file, failureMode, evidence, mode: "backfill", status: "pending"}`. omit `score`, the next sweep scores it. missing file -> create as `[]` first, that's a cold start not an error

suite stays green, branch stays PR-safe to CyberDrain/CIPP.

## 6. report

- tests added, each with the failure mode it pins and which proof it passed
- gaps declined, with the reason
- anything queued to findings/backlog
- suggested `test:` commit message, then stop. never commit to `CIPP\` yourself

## out of scope

- bulk backfill across the frontend, that is `/test-sweep`
- fixing bugs beyond the change already in flight
- backend Pester, e2e against the live stack
- rewriting or deleting tests that predate this run. deletion applies only to tests written this run that failed their proof, a weak pre-existing test gets reported, not removed
