import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../test-utils'
import Page from '../../src/pages/cipp/advanced/worker-health.js'

// stable refs, see GraphExplorerPage.test.jsx (fresh literals per call loop the data-sync effects)
const jobsResult = vi.hoisted(() => ({
  isSuccess: true,
  isFetching: false,
  isLoading: false,
  isError: false,
  data: {
    pages: [
      {
        Results: [
          { Id: 'j1', Name: 'Job One', RunName: 'run-a', Priority: 1, Status: 'Queued', QueuedUtc: '2026-07-30T10:00:00Z', WaitSeconds: 5, DurationSeconds: 0 },
          { Id: 'j2', Name: 'Job Two', RunName: 'run-a', Priority: 1, Status: 'Queued', QueuedUtc: '2026-07-30T10:01:00Z', WaitSeconds: 3, DurationSeconds: 0 },
          { Id: 'j3', Name: 'Job Three', RunName: 'run-b', Priority: 2, Status: 'Running', QueuedUtc: '2026-07-30T10:02:00Z', WaitSeconds: 1, DurationSeconds: 4 },
          { Id: 'j4', Name: 'Job Four', RunName: 'run-b', Priority: 2, Status: 'Completed', QueuedUtc: '2026-07-30T10:03:00Z', WaitSeconds: 1, DurationSeconds: 9 },
          { Id: 'j5', Name: 'Job Five', RunName: 'run-c', Priority: 3, Status: 'Completed', QueuedUtc: '2026-07-30T10:04:00Z', WaitSeconds: 2, DurationSeconds: 7 },
        ],
      },
    ],
  },
  fetchNextPage: vi.fn(),
  refetch: vi.fn(),
}))

const emptyGetResult = vi.hoisted(() => ({
  isSuccess: false,
  isFetching: false,
  isLoading: false,
  isError: false,
  data: undefined,
  refetch: vi.fn(),
}))

vi.mock('../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(() => emptyGetResult),
  ApiPostCall: vi.fn(() => ({ mutate: vi.fn(), isPending: false, isSuccess: false, isError: false, data: undefined, error: null })),
  ApiGetCallWithPagination: vi.fn(() => jobsResult),
}))

describe('Worker Health page - job queue preset filters', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders the job queue with all rows', async () => {
    renderWithProviders(<Page />)
    expect(await screen.findByText('Job Queue')).toBeInTheDocument()
    expect(await screen.findByText('1-5 of 5')).toBeInTheDocument()
  })

  it('Queued preset filters the table to queued jobs', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />)
    await screen.findByText('1-5 of 5')

    await user.click(screen.getByRole('button', { name: 'Filters' }))
    await user.click(await screen.findByRole('menuitem', { name: 'Queued' }))

    await waitFor(() => {
      expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
    })
  })

  it('Running preset filters the table to running jobs', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />)
    await screen.findByText('1-5 of 5')

    await user.click(screen.getByRole('button', { name: 'Filters' }))
    await user.click(await screen.findByRole('menuitem', { name: 'Running' }))

    await waitFor(() => {
      expect(screen.getByText('1-1 of 1')).toBeInTheDocument()
    })
  })

  // presets saved before they carried type: "column" persisted a column-filter array into the
  // GLOBAL filter slot (stringifies to "[object Object]", matches zero rows). restore must
  // ignore that garbage and preset clicks must still work
  // pins parked branch fix/table-preset-filter-reset, unskip when it lands (upstream-findings #28)
  it.skip('ignores a stale persisted legacy global filter, presets still work', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Page />, {
      settings: {
        currentTenant: 'testdomain.com',
        currentTheme: { value: 'light', label: 'light' },
        paletteMode: 'light',
        direction: 'ltr',
        pinNav: true,
        handleUpdate: () => {},
        handleReset: () => {},
        isCustom: false,
        persistFilters: true,
        // pageName resolves to '' under the router mock (pathname '/')
        lastUsedFilters: { '': { type: 'global', value: [{ id: 'Status', value: 'Queued' }], name: 'Queued' } },
        setLastUsedFilter: () => {},
      },
    })
    await screen.findByText('1-5 of 5')

    // restore effect fires 100ms after mount, garbage global value must not empty the table
    await new Promise((resolve) => setTimeout(resolve, 300))
    expect(screen.getByText('1-5 of 5')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Filters' }))
    await user.click(await screen.findByRole('menuitem', { name: 'Queued' }))

    await waitFor(() => {
      expect(screen.getByText('1-2 of 2')).toBeInTheDocument()
    }, { timeout: 3000 })
  }, 20000)
})
