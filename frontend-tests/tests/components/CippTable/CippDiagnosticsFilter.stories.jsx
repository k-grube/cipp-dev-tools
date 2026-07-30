import { fn, within, expect, userEvent, waitFor } from 'storybook/test'
import { http, HttpResponse } from 'msw'
import CippDiagnosticsFilter from '../../../src/components/CippTable/CippDiagnosticsFilter'

const mswHandlers = [
  http.get('/api/ListDiagnosticsPresets', () => {
    return HttpResponse.json([
      { GUID: 'a1b2c3d4-1234-5678-9012-abcdef123456', name: 'Exchange Health Check', query: 'traces | where message contains "Exchange"' },
      { GUID: 'b2c3d4e5-2345-6789-0123-bcdef1234567', name: 'License Report', query: 'traces | where message contains "License"' },
    ])
  }),
  http.post('/api/ExecDiagnosticsPresets', () => {
    return HttpResponse.json({ Results: 'Preset saved' })
  }),
]

export default {
  title: 'Components/CippTable/CippDiagnosticsFilter',
  component: CippDiagnosticsFilter,
  tags: ['autodocs'],
  parameters: {
    msw: {
      handlers: mswHandlers,
    },
  },
}

export const Default = {
  args: {
    onSubmitFilter: fn(),
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)

    await expect(canvas.getByText('Query')).toBeVisible()
    await expect(canvas.getByText('Requirements')).toBeVisible()

    // Execute button should be disabled with no query
    const executeButton = canvas.getByRole('button', { name: /execute query/i })
    await expect(executeButton).toBeDisabled()
  },
}

export const ExecuteQuery = {
  args: {
    onSubmitFilter: fn(),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement)

    // Type a query into the KQL field
    const queryInput = canvas.getByPlaceholderText(/enter your kql query/i)
    await userEvent.click(queryInput)
    await userEvent.type(queryInput, 'traces | where timestamp > ago(1h)')

    // Execute button should now be enabled
    const executeButton = canvas.getByRole('button', { name: /execute query/i })
    await waitFor(() => {
      expect(executeButton).toBeEnabled()
    })

    await userEvent.click(executeButton)

    await waitFor(() => {
      expect(args.onSubmitFilter).toHaveBeenCalledWith(
        expect.objectContaining({
          query: 'traces | where timestamp > ago(1h)',
        })
      )
    })
  },
}

export const ClearQuery = {
  args: {
    onSubmitFilter: fn(),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement)

    // Type a query
    const queryInput = canvas.getByPlaceholderText(/enter your kql query/i)
    await userEvent.click(queryInput)
    await userEvent.type(queryInput, 'some query')

    // Click clear
    const clearButton = canvas.getByRole('button', { name: /clear/i })
    await userEvent.click(clearButton)

    // onSubmitFilter should be called with empty query
    await waitFor(() => {
      expect(args.onSubmitFilter).toHaveBeenCalledWith(
        expect.objectContaining({
          query: '',
        })
      )
    })
  },
}
