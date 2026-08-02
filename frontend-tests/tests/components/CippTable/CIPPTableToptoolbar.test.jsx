import React from 'react'
import { describe, it, expect, vi } from 'vitest'
import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../../test-utils'
import { CippDataTable } from '../../../src/components/CippTable/CippDataTable'

// upstream-findings #34: saved preset doesn't appear in the Filters dropdown until
// reload. the filterList effect deps on presetList.isSuccess only; a background
// refetch after save-preset invalidation swaps data without an isSuccess
// transition, so the dropdown never rebuilds

vi.mock('../../../src/api/ApiCall', async () => (await import('../../mocks/api-call')).apiCallMock())
import { api, getResult, paginatedResult, postResult } from '../../mocks/api-call'

const refreshRows = [
  { displayName: 'Alice Smith', mail: 'alice@contoso.com' },
  { displayName: 'Bob Johnson', mail: 'bob@contoso.com' },
]

// stable refs per phase, fresh literals per call loop the data-sync effects
const emptyPresets = getResult({ data: { Results: [] } })
const savedPresets = getResult({
  data: {
    Results: [{ id: 'p1', name: 'My Saved Preset', params: { endpoint: 'testWidgets' } }],
  },
})
const emptyGetResult = getResult({ isSuccess: false })
const tableData = paginatedResult(refreshRows)

let presetsResult = emptyPresets
api.get = (opts) => (opts.url === '/api/ListGraphExplorerPresets' ? presetsResult : emptyGetResult)
api.paginated = tableData
api.post = postResult()

const graphTable = (
  <CippDataTable
    api={{ url: '/api/ListGraphRequest', dataKey: 'Results', data: { Endpoint: 'testWidgets' } }}
    queryKey="PresetRefreshTest"
    simpleColumns={['displayName', 'mail']}
    filters={[]}
    maxHeightOffset="100px"
  />
)

const rows = [
  { displayName: 'Alice Smith', mail: 'alice@contoso.com', department: 'IT' },
  { displayName: 'Bob Johnson', mail: 'bob@contoso.com', department: 'Sales' },
  { displayName: 'Carol Williams', mail: 'carol@contoso.com', department: 'IT' },
]

const tablePresets = [
  { filterName: 'IT only', value: [{ id: 'department', value: 'IT' }], type: 'column' },
  { filterName: 'Sales only', value: [{ id: 'department', value: 'Sales' }], type: 'column' },
]

const graphPresetResult = getResult({
  data: {
    Results: [
      { id: 'gp-1', name: 'Widget View', params: { endpoint: 'testWidgets', $filter: "state eq 'on'" } },
    ],
  },
})

function renderGraphTable(extraProps = {}) {
  return renderWithProviders(
    <CippDataTable
      api={{ url: '/api/ListGraphRequest', dataKey: 'Results', data: { Endpoint: 'testWidgets' } }}
      queryKey="SlotsTest"
      simpleColumns={['displayName', 'mail', 'department']}
      filters={tablePresets}
      maxHeightOffset="100px"
      {...extraProps}
    />
  )
}

describe('CIPPTableToptoolbar - preset list refresh', () => {
  it('shows a newly saved preset in the Filters dropdown without a remount', async () => {
    const user = userEvent.setup()
    renderWithProviders(graphTable)
    await screen.findByText('1-2 of 2')

    // preset not saved yet, menu opens without it
    await user.click(screen.getByRole('button', { name: 'Filters' }))
    await screen.findByRole('menuitem', { name: 'Reset all filters' })
    expect(screen.queryByRole('menuitem', { name: 'My Saved Preset' })).toBeNull()
    await user.keyboard('{Escape}')

    // save-preset invalidation refetches: same isSuccess, new data identity.
    // reopening the menu re-renders the toolbar, which is all a background
    // refetch does, and matches the real repro (reopening doesn't help)
    presetsResult = savedPresets
    await user.click(screen.getByRole('button', { name: 'Filters' }))
    await screen.findByRole('menuitem', { name: 'My Saved Preset' }, { timeout: 3000 })
  }, 15000)
})
