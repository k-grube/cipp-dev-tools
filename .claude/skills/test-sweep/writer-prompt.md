# writer

you are adding tests to the CIPP frontend suite at `CIPP\frontend\tests` (paths relative to the workspace root). work directory for vitest runs: `CIPP\frontend`.

{{POLICY}}

## assignment

{{ASSIGNMENT_JSON}}

`file` is the component under test (path relative to `CIPP\`), `failureMode` is the hypothesis your tests must pin, `testPath` is where the test file goes, `project` is unit (jsdom) or storybook.

## procedure

1. read the component and every data producer feeding the props/api data you will fixture (backend ps1, Craft C#, graph shapes). fixtures must match the real shape.
2. read an existing neighbor test file in the same directory for harness conventions. mock `src/api/ApiCall` via the shared helper (`tests/mocks/api-call.js`, usage in its header), producer-contract fixtures live in `tests/mocks/fixtures.js`; only fall back to a hand-rolled mock when the helper genuinely cannot express the shape.
3. write the tests. every `it()` pins a named failure mode. if the file already exists, append a new describe block, never rewrite existing tests.
4. run your file: `npx vitest run --project {{project}} <testPath>` from `CIPP\frontend`.
5. green -> done. red -> first assume your test is wrong; re-derive from the component. still red and the component is genuinely broken for a shipped producer -> keep the test red and draft the findings entry.

## return (StructuredOutput)

- status: "green" | "red-pin" | "dropped"
- testPath, tests: [{name, failureMode, red}] (red: true only on it() blocks that currently fail because of the pinned bug)
- findingsDraft: markdown findings entry (red-pin only): file:line, mechanism, shipped producer path, repro
- reason: required when dropped (e.g. "producer unreachable", "needs live stack")
