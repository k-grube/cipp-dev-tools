# frontend test policy

single source for the CIPP frontend test value bar. read directly by `/component-tests`; the rules sections below are injected into test-sweep's writer prompts, this title and preamble are maintainer-facing and stay out of prompts. keep it self-contained: no placeholders, no references to either skill's internals.

## hard rules

- every `it()` pins a named failure mode: the test fails if that specific bug is (re)introduced, and the name says what breaks ("preset filters queued rows", not "renders table")
- forbidden: render-smoke tests, snapshots, MUI-internal assertions, style assertions, synthetic producer rows (find the shipped producer or drop the target), per-call waitFor timeouts
- fixtures match the real producer shape: read the backend ps1 / Craft C# / graph producer before writing the fixture. `spec/cipp-openapi-v2.json` helps, code is authoritative
- nothing that needs the live dev stack
- read `spec/toolchain-notes.md` before writing (jsdom/MRT/coverage traps), and `CIPP/frontend/tests/test-utils.jsx` for providers
- follow repo comment/style conventions: terse lowercase comments, no decorative markers, ASCII ->, braces on all control flow

## jsdom vs storybook

quoted from CIPP `docs/dev-documentation/cipp-dev-guide/frontend-testing.md`:

> - If you are asserting render branches, prop handling, text output, or utility functions, write a `.test.jsx` file in jsdom. These are fast, need no browser, and heavy child components can be mocked with `vi.mock`.
> - If the component needs real layout, scrolling, portals, or browser APIs that jsdom can't fake (the Material React Table row virtualizer, drag interactions), write a story with a `play()` function that asserts the behavior. The storybook project runs every story in Chromium.
> - A story that is purely visual documentation is fine too, it still counts as a render smoke test. It will catch a crash, but nothing subtler.
> - Prefer asserting output and behavior over presence. A dependency bump that changes *what* renders (not *whether* it renders) should fail a test.

default jsdom. a purely-visual story never satisfies the value bar on its own.
