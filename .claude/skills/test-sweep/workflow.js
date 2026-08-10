export const meta = {
  name: 'test-sweep-run',
  description: 'Fan out test writers over backlog assignments, adversarially verify, gate on the full suite',
  phases: [{ title: 'Write' }, { title: 'Verify' }, { title: 'Gate' }],
}

const WRITE_SCHEMA = {
  type: 'object',
  required: ['status', 'testPath', 'tests'],
  properties: {
    status: { enum: ['green', 'red-pin', 'dropped'] },
    testPath: { type: 'string' },
    tests: { type: 'array', items: { type: 'object', required: ['name', 'failureMode'], properties: { name: { type: 'string' }, failureMode: { type: 'string' }, red: { type: 'boolean' } } } },
    findingsDraft: { type: 'string' },
    reason: { type: 'string' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['verdicts', 'survivingTests', 'redPinValid'],
  properties: {
    verdicts: { type: 'array', items: { type: 'object', required: ['name', 'confirmed', 'reason'], properties: { name: { type: 'string' }, confirmed: { type: 'boolean' }, reason: { type: 'string' } } } },
    redPinValid: { type: ['boolean', 'null'] },
    survivingTests: { type: 'integer' },
  },
}

const GATE_SCHEMA = {
  type: 'object',
  required: ['passed', 'failures', 'runtimeSeconds'],
  properties: {
    passed: { type: 'boolean' },
    failures: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, name: { type: 'string' } } } },
    flakes: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, name: { type: 'string' } } } },
    runtimeSeconds: { type: 'number' },
  },
}

const fill = (tpl, slots) => Object.entries(slots).reduce((s, [k, v]) => s.replaceAll(`{{${k}}}`, () => v), tpl)

// args can arrive json-encoded, normalize before use
const input = typeof args === 'string' ? JSON.parse(args) : args

// write -> verify per assignment, no barrier between assignments
const results = await pipeline(
  input.assignments,
  (a) =>
    agent(fill(input.writerPrompt, { ASSIGNMENT_JSON: JSON.stringify(a, null, 2), project: a.project }), {
      label: `write:${a.file.split('/').pop()}`,
      phase: 'Write',
      schema: WRITE_SCHEMA,
    }).then((write) => ({ assignment: a, write })),
  (r, a) => {
    if (!r || !r.write || r.write.status === 'dropped') {
      return r
    }
    return agent(
      fill(input.verifierPrompt, { RESULT_JSON: JSON.stringify({ assignment: a, write: r.write }, null, 2), project: a.project }),
      { label: `verify:${a.file.split('/').pop()}`, phase: 'Verify', schema: VERIFY_SCHEMA }
    ).then((verify) => ({ ...r, verify }))
  }
)

const kept = results.filter(Boolean)
const expectedRed = kept
  .filter((r) => r.write?.status === 'red-pin' && r.verify?.redPinValid)
  .flatMap((r) => r.write.tests.filter((t) => t.red).map((t) => ({ file: r.write.testPath, name: t.name })))
const anyStorybook = input.assignments.some((a) => a.project === 'storybook')

const gate = await agent(
  fill(input.gatePrompt, {
    EXPECTED_RED_JSON: JSON.stringify([...(input.priorRedPins ?? []), ...expectedRed]),
    // skip the chromium project unless an assignment targeted it
    UNIT_ONLY: anyStorybook ? '' : ' --unit',
  }),
  { label: 'gate:full-suite', phase: 'Gate', schema: GATE_SCHEMA }
)

return { results: kept, gate }
