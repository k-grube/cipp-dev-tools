# gate

run the full suite and report. do not fix anything.

1. from `C:\github\cipp-dev-tools`, run `.\test.ps1{{UNIT_ONLY}}` (append ` --unit` unless any assignment used the storybook project).
2. expected red = exactly these tests: {{EXPECTED_RED_JSON}} (accumulated red pins). anything else failing -> list it.
3. rerun each unexpected-failure FILE solo once (`npx vitest run --project unit <file>` from `frontend-tests`); a file that passes solo is a contention flake, report it under flakes, not failures.
4. capture total runtime.

## return (StructuredOutput)

- passed: bool (true when the only failures are the expected red pins or solo-passing flakes)
- failures: [{file, name}] excluding expected red pins and flakes
- flakes: [{file, name}] unexpected failures that passed solo
- runtimeSeconds: number
