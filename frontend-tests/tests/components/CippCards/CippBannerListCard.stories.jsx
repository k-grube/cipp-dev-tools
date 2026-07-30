import { fn, within, expect, userEvent, waitFor } from 'storybook/test'
import { CippBannerListCard } from '../../../src/components/CippCards/CippBannerListCard'

const userPropertyItems = [
  { label: 'Display Name', value: 'Alice Smith' },
  { label: 'UPN', value: 'alice@contoso.com' },
  { label: 'Department', value: 'Engineering' },
  { label: 'Job Title', value: 'Senior Developer' },
  { label: 'Location', value: 'Seattle, WA' },
  { label: 'Account Enabled', value: 'Yes' },
  { label: 'MFA Status', value: 'Enabled' },
  { label: 'Last Sign-In', value: '2026-04-05T14:30:00Z' },
]

const bannerListItems = [
  {
    id: '1',
    cardLabelBox: { cardLabelBoxHeader: '15', cardLabelBoxText: 'Apr' },
    text: 'Password Expiration Policy',
    subtext: 'Applies to all users in contoso.com',
    statusText: 'Enabled',
    statusColor: 'success.main',
  },
  {
    id: '2',
    cardLabelBox: { cardLabelBoxHeader: '22', cardLabelBoxText: 'Mar' },
    text: 'Conditional Access - Require MFA',
    subtext: 'All users, all cloud apps',
    statusText: 'Report Only',
    statusColor: 'warning.main',
  },
  {
    id: '3',
    cardLabelBox: 'CA',
    text: 'Block Legacy Authentication',
    subtext: 'Exchange ActiveSync, POP3, IMAP',
    statusText: 'Disabled',
    statusColor: 'error.main',
  },
]

export default {
  title: 'Components/CippCards/CippBannerListCard',
  component: CippBannerListCard,
  tags: ['autodocs'],
  argTypes: {
    isFetching: { control: 'boolean' },
    isCollapsible: { control: 'boolean' },
  },
}

export const Basic = {
  args: {
    items: bannerListItems,
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByText('Password Expiration Policy')).toBeVisible()
    await expect(canvas.getByText('Conditional Access - Require MFA')).toBeVisible()
    await expect(canvas.getByText('Enabled')).toBeVisible()
    await expect(canvas.getByText('Report Only')).toBeVisible()
    await expect(canvas.getByText('Disabled')).toBeVisible()
  },
}

export const Collapsible = {
  args: {
    isCollapsible: true,
    items: [
      {
        ...bannerListItems[0],
        propertyItems: userPropertyItems,
      },
      bannerListItems[1],
      bannerListItems[2],
    ],
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByText('Password Expiration Policy')).toBeVisible()

    const expandButtons = canvas.getAllByRole('button')
    await userEvent.click(expandButtons[0])

    await waitFor(() => {
      expect(canvas.getByText('Display Name')).toBeVisible()
    })
    expect(canvas.getByText('Alice Smith')).toBeVisible()
  },
}

export const WithSelection = {
  args: {
    items: bannerListItems,
    onSelectionChange: fn(),
    selectedItems: [],
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement)
    const checkboxes = canvas.getAllByRole('checkbox')
    await expect(checkboxes).toHaveLength(3)

    await userEvent.click(checkboxes[0])
    await expect(args.onSelectionChange).toHaveBeenCalledWith(['1'])
  },
}

export const Loading = {
  args: {
    items: bannerListItems,
    isFetching: true,
  },
}

export const Empty = {
  args: {
    items: [],
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByText('No items available.')).toBeVisible()
  },
}
