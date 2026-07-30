import React from 'react'
import { within, expect, waitFor } from 'storybook/test'
import { http, HttpResponse } from 'msw'
import UnauthenticatedPage from '../../src/pages/unauthenticated'

export default {
  title: 'Pages/Unauthenticated',
  component: UnauthenticatedPage,
  tags: ['autodocs'],
}

export const AccessDenied = {
  render: () => <UnauthenticatedPage />,
  parameters: {
    msw: {
      handlers: [
        http.get('/api/me', () => {
          return HttpResponse.json({ message: 'Permission Denied' })
        }),
        http.get('/.auth/me', () => {
          return HttpResponse.json({ clientPrincipal: null })
        }),
        http.get('*/api/me', () => {
          return HttpResponse.json({ message: 'Permission Denied' })
        }),
        http.get('*/.auth/me', () => {
          return HttpResponse.json({ clientPrincipal: null })
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await waitFor(() => {
      expect(canvas.getByText('Access Denied')).toBeInTheDocument()
    })
    await expect(canvas.getByText('Permission Denied')).toBeInTheDocument()
    const loginButton = canvas.getByRole('link', { name: /Login/i })
    await expect(loginButton).toBeInTheDocument()
  },
}
