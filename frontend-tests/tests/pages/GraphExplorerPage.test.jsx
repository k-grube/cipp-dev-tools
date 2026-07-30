import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../test-utils'
import Page from '../../src/pages/tenant/tools/graph-explorer/index.js'
import { ApiGetCallWithPagination } from '../../src/api/ApiCall'

// CippDataTable/CippAutoComplete key effects off the raw data object; a factory returning a fresh literal each call spins Maximum update depth exceeded, so paginatedResult must stay the same reference
const paginatedResult = vi.hoisted(() => ({
  isSuccess: true,
  isFetching: false,
  isLoading: false,
  isError: false,
  data: { pages: [{ Results: [] }] },
  fetchNextPage: vi.fn(),
  refetch: vi.fn(),
}))

vi.mock('../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(() => ({ isSuccess: false, isFetching: false, data: undefined, refetch: vi.fn() })),
  ApiPostCall: vi.fn(() => ({ mutate: vi.fn(), isPending: false, isSuccess: false, isError: false, data: undefined, error: null })),
  ApiGetCallWithPagination: vi.fn(() => paginatedResult),
}))

// monaco never resolves in jsdom; canonical mock copied verbatim from CippCodeBlock.test.jsx
vi.mock('@monaco-editor/react', () => ({
  Editor: ({ value, language }) => (
    <div data-testid="monaco-editor" data-language={language}>{value}</div>
  ),
}))

const settingsWith = (tenant) => ({
  currentTenant: tenant,
  currentTheme: { value: 'light', label: 'light' },
  paletteMode: 'light',
  direction: 'ltr',
  pinNav: true,
  handleUpdate: () => {},
  handleReset: () => {},
  isCustom: false,
})

describe('Graph Explorer page', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders the filter bar and the table view by default', async () => {
    renderWithProviders(<Page />)
    expect(screen.getByRole('combobox', { name: 'Select a query' })).toBeInTheDocument()
    // table title carries the tenant suffix
    expect(await screen.findByText('Graph Explorer - testdomain.com')).toBeInTheDocument()
    expect(screen.queryByTestId('monaco-editor')).not.toBeInTheDocument()
  })

  it('json mode renders the code editor instead of the table', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />)
    await user.click(screen.getByRole('button', { name: 'View JSON' }))
    expect(await screen.findByTestId('monaco-editor')).toBeInTheDocument()
    expect(screen.queryByText('Graph Explorer - testdomain.com')).not.toBeInTheDocument()
  })

  it('filter bar survives the view toggle (single mount, drawer-state fix)', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />)
    const combo = screen.getByRole('combobox', { name: 'Select a query' })
    await user.click(combo)
    await user.click(await screen.findByRole('option', { name: 'All users with email addresses' }))
    // selecting remounts the input (defaultValue change recomputes CippAutoComplete's memoized key), re-query instead of reusing combo
    expect(screen.getByRole('combobox', { name: 'Select a query' })).toHaveValue('All users with email addresses')
    await user.click(screen.getByRole('button', { name: 'View JSON' }))
    await screen.findByTestId('monaco-editor')
    await user.click(screen.getByRole('button', { name: 'View Table' }))
    // a remounted bar would have reset this to empty
    expect(screen.getByRole('combobox', { name: 'Select a query' })).toHaveValue(
      'All users with email addresses'
    )
  }, 15000) // heaviest test in the file (MRT mount + autocomplete remount + monaco Suspense); default 5000ms flakes under full-suite worker contention

  it('warns when no tenant is selected in table mode', () => {
    renderWithProviders(<Page />, { settings: settingsWith(null) })
    expect(
      screen.getByText('No tenant selected. Please select a tenant from the dropdown above.')
    ).toBeInTheDocument()
  })

  it('does not warn when a tenant is selected', () => {
    renderWithProviders(<Page />)
    expect(screen.queryByText(/No tenant selected/)).not.toBeInTheDocument()
  })

  it('running a preset updates the page title', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />)
    await user.click(screen.getByRole('combobox', { name: 'Select a query' }))
    await user.click(await screen.findByRole('option', { name: 'All users with email addresses' }))
    await user.click(screen.getByRole('button', { name: 'Run' }))
    expect(
      await screen.findByText('Graph Explorer - All users with email addresses - testdomain.com')
    ).toBeInTheDocument()
  })

  it('running a preset sends tenant and filter params to ListGraphRequest', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />)
    await user.click(screen.getByRole('combobox', { name: 'Select a query' }))
    await user.click(await screen.findByRole('option', { name: 'All users with email addresses' }))
    await user.click(screen.getByRole('button', { name: 'Run' }))
    await waitFor(() => {
      expect(ApiGetCallWithPagination).toHaveBeenCalledWith(
        expect.objectContaining({
          url: '/api/ListGraphRequest',
          data: expect.objectContaining({
            tenantFilter: 'testdomain.com',
            endpoint: '/users',
            $select: 'userPrincipalName,mail,proxyAddresses',
          }),
        })
      )
    })
  })
})
