import React from 'react'
import { describe, it, expect, vi } from 'vitest'
import { screen, waitFor, within } from '@testing-library/react'
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

const rows = [
  { displayName: 'Alice Smith', mail: 'alice@contoso.com', department: 'IT' },
  { displayName: 'Bob Johnson', mail: 'bob@contoso.com', department: 'Sales' },
  { displayName: 'Carol Williams', mail: 'carol@contoso.com', department: 'IT' },
]

const tablePresets = [
  { filterName: 'IT only', value: [{ id: 'department', value: 'IT' }], type: 'column' },
  { filterName: 'Sales only', value: [{ id: 'department', value: 'Sales' }], type: 'column' },
]

// stable refs per phase, fresh literals per call loop the data-sync effects
const emptyPresets = getResult({ data: { Results: [] } })
const savedPresets = getResult({
  data: {
    Results: [{ id: 'p1', name: 'My Saved Preset', params: { endpoint: 'testWidgets' } }],
  },
})
const graphPresetResult = getResult({
  data: {
    Results: [
      { id: 'gp-1', name: 'Widget View', params: { endpoint: 'testWidgets', $filter: "state eq 'on'" } },
    ],
  },
})
const emptyGetResult = getResult({ isSuccess: false })
const tableData = paginatedResult(refreshRows)
const slotsTableData = paginatedResult(rows)

let presetsResult = emptyPresets
api.get = (opts) => (opts.url === '/api/ListGraphExplorerPresets' ? presetsResult : emptyGetResult)
// route by queryKey: renderGraphTable's table gets the 3-row fixture (including the
// key swap a graph preset causes, 'SlotsTest-<filterName>'), the #34 table keeps its 2-row one
api.paginated = (opts) => (opts.queryKey?.startsWith('SlotsTest') ? slotsTableData : tableData)
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

function renderGraphTable(extraProps = {}) {
  // pin the preset route here so renderGraphTable-based tests see 'Widget View'
  // regardless of what an earlier test left presetsResult pointing at
  presetsResult = graphPresetResult
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
    presetsResult = emptyPresets // order-independent: not relying on the module-scope initial value
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

  it('graph preset and column preset are both marked active', async () => {
    const user = userEvent.setup()
    renderGraphTable()
    await screen.findByText('1-3 of 3')

    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'Widget View' }))
    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'IT only' }))

    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await waitFor(() => {
      // scope to the live accessible menu: a closing menu's DOM can linger
      // (aria-hidden, unmount pending) and would otherwise double-count
      const menu = within(screen.getByRole('menu'))
      expect(menu.getAllByTestId('CheckIcon').length).toBeGreaterThanOrEqual(2)
    })
  }, 15000)

  it('applying a graph preset keeps the column filter applied', async () => {
    const user = userEvent.setup()
    renderGraphTable()
    await screen.findByText('1-3 of 3')

    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'IT only' }))
    await waitFor(() => {
      expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
    })

    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'Widget View' }))
    // same mocked rows come back under the swapped queryKey, column filter must survive
    await waitFor(() => {
      expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
    })
  }, 15000)

  it('clicking the active graph preset toggles it off and keeps the column filter', async () => {
    const user = userEvent.setup()
    renderGraphTable()
    await screen.findByText('1-3 of 3')

    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'Widget View' }))
    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'IT only' }))
    await waitFor(() => {
      expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
    })

    // second click on the active graph preset = toggle off, column filter survives on base data
    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'Widget View' }))
    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await waitFor(() => {
      // scope to the live accessible menu, same reason as the dual-slot pin above
      const menu = within(screen.getByRole('menu'))
      expect(menu.getAllByTestId('CheckIcon')).toHaveLength(1)
    })
    expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
  }, 20000)

  it('clicking the active column preset toggles back to unfiltered rows', async () => {
    const user = userEvent.setup()
    renderGraphTable()
    await screen.findByText('1-3 of 3')

    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'IT only' }))
    await waitFor(() => {
      expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
    })
    await user.click(screen.getByRole('button', { name: /Filters/ }))
    await user.click(await screen.findByRole('menuitem', { name: 'IT only' }))
    await waitFor(() => {
      expect(screen.getByText('1-3 of 3')).toBeInTheDocument()
    })
  }, 15000)
})
