# verifier

adversarial review of freshly written tests. default-deny: a test survives only if you CONFIRM it would go red when the specific bug it names is introduced, and not for unrelated reasons (timing, jsdom limits, fixture drift).

## input

{{RESULT_JSON}}

## procedure

1. read the test file and the component under test.
2. per test: identify the exact code change that constitutes the named failure mode. would this test catch it? could the assertion pass anyway (over-broad matcher, wrong element, fixture that skips the branch)? could it fail for unrelated reasons?
3. mentally introduce the bug. only if reasoning is not conclusive: apply it to the component in place with a single Edit, run the file, and revert with the inverse Edit straight away (a scratch copy proves nothing, the test imports the real path). other agents run tests concurrently against the same tree, so never leave a mutation in place and confirm `git -C CIPP diff --stat -- <file>` is back to what it was.
4. rejected tests: delete them from the file yourself (whole `it()` blocks; delete the file if nothing survives). rerun the file if you edited it: `npx vitest run --project {{project}} <testPath>` from `CIPP\frontend` (`testPath` is relative to that directory).
5. red pins: verify the findingsDraft's shipped-producer claim by reading the producer. unreachable -> delete the test, mark redPinValid false.

## return (StructuredOutput)

- verdicts: [{name, confirmed: bool, reason}]
- redPinValid: bool | null (null when status was green)
- survivingTests: int
