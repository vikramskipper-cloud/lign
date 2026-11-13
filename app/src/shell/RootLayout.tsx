import { Outlet } from 'react-router'
import { AppShell } from '@/shell/AppShell'
import { AsyncBoundary } from '@/ui/async-boundary'
import { ErrorBoundary } from '@/ui/error-boundary'
import { RealtimeProvider } from '@/features/realtime/RealtimeProvider'

/**
 * Everything an authenticated route sits inside: error boundary, realtime
 * connection, the shared chrome, and a suspense boundary around the page.
 *
 * The root shell owns global navigation. WorkspaceLayout and ProjectLayout
 * own their contextual navigation inside the main content.
 *
 * Note that /dashboard now routes through here too. It previously sat outside
 * this layout with its own shell, which quietly meant Home had no error
 * boundary and no realtime connection.
 */
export function RootLayout() {
  return (
    <ErrorBoundary>
      <RealtimeProvider>
        <AppShell>
          <AsyncBoundary>
            <Outlet />
          </AsyncBoundary>
        </AppShell>
      </RealtimeProvider>
    </ErrorBoundary>
  )
}
