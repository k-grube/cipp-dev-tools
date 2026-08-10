# toolchain notes (frontend test harness session, 2026-07-23)

non-obvious findings worth knowing before touching the frontend test/build toolchain. bugs live in `docs\upstream-findings.md` (local-only, not in this repo), branch state in session memory. paths relative to `cipp\` unless noted.

## yarn / registry

- lock `resolved` urls come from the registry metadata's `dist.tarball`, which always says `registry.npmjs.org` (even via the yarnpkg mirror)
- yarn classic rewrites npmjs -> yarnpkg in the lock only when the configured registry `===` `https://registry.yarnpkg.com` exactly, NO trailing slash (`cleanRegistry` in yarn source, strict string match). trailing slash silently disables the rewrite
- `frontend/.npmrc` + `frontend/.yarnrc` are committed upstream and pin the registry (user set them to the no-slash yarnpkg url). upstream lock is mixed npmjs/yarnpkg, don't mass-rewrite it
- yarnpkg.com was never deprecated: yarnpkg/yarn#5891 closed 2019 with "keeping the CNAME up for the foreseeable future", still yarn's default

## vite / vitest / storybook

- vite 8 is rolldown-based and ignores `esbuild` config entirely. this codebase is JSX-in-`.js`, all three loader overrides depend on `esbuild.loader: 'jsx'`, so vite is pinned 7.3.6 via `resolutions` (yarn v1 otherwise nests vite 8 under vitest). unpin after the jsx-in-js rename
- vitest 4: `@vitest/browser` is gone, playwright provider is `@vitest/browser-playwright` and `browser.provider` takes the imported `playwright()`, not a string
- `@storybook/addon-vitest` (thru 10.5.3) still calls the deprecated `vitest.init()`, the "use vitest.standalone()" warning is upstream storybook's problem, ignore it
- `yarn test:coverage` merges both projects into one report, browser coverage works via CDP in chromium. story-only components show real percentages (that's the proof it merges)
- coverage instrumentation slows lazy chunks/fetches past testing-library's 1s default `waitFor`. global `asyncUtilTimeout: 10000` set in `frontend/vitest.setup.js` and `frontend/.storybook/vitest.setup.js`, never add per-call timeouts

## test-writing gotchas

- `sb.mock()` in a story file is a silent no-op, storybook only extracts sb.mock calls from the preview config. the old Layout story "mocked" ApiCall this way and never tested what it claimed. use story-level msw handlers + seed the react-query cache instead
- MUI outlined inputs render the label text twice (label + fieldset legend), `getByLabelText` throws multiple-match. use `getByRole('textbox', { name: ... })`
- `next/dynamic` components never resolve in jsdom without the alias mock (`tests/mocks/next-dynamic.js`, React.lazy + Suspense), and their assertions must be async
- react-hooks lint rejects `ref.current = x` in component bodies (test harnesses included), assign in a `useEffect`
- vi.mock of `src/api/ApiCall` must export `ApiGetCall`, `ApiPostCall`, AND `ApiGetCallWithPagination`, deep component trees pull all three
- CippDataTable can't be driven through row selection in jsdom, MRT's row + column virtualizers measure 0 so zero `th` and zero `tbody tr` render and the select-all checkbox is unreachable. render `CIPPTableToptoolbar` directly against a real `useMaterialReactTable` instance and call `table.toggleAllRowsSelected(true)` (same api the checkbox calls), after mount because the toolbar's effect on `[usedData]` clears selection on mount. the toolbar is `React.memo`, so at least one prop must change identity per render (pass `getRequestData` as an inline literal)
- `require.context` needs the `cipp-require-context` pre-plugin in `vitest.config.mjs` (unit project), not just `tests/mocks/require-context.js`, vitest's per-module cjs `require` shadows the globalThis patch

## picking what to test

- rank candidates by graph degree: load `graphify-out/graph.json` (node-link format, edges under `links`), sum degree per `source_file` under `frontend/src/components`. this found CippTablePage (#2, zero tests) after the reviews missed it
- the dev stack rewrites `backend/Modules/*/[Name].psd1` manifests (`App__Worker__DevExpandModuleExports` in `build/docker-compose-all.yml`), CIPPTests.psd1 showing modified is stack noise, never commit it
