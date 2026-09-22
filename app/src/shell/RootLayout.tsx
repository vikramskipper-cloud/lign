import { Outlet } from 'react-router'
import { AppShell } from '@/shell/AppShell'
import { AsyncBoundary } from '@/ui/async-boundary'
import { ErrorBoundary } from '@/ui/error-boundary'
import { RealtimeProvider } from '@/features/realtime/RealtimeProvider'

/**
 * Everything an authenticated route sits inside: error boundary, realtime
 * connection, the shared chrome, and a suspense boundary around the page.
 *
 * The nav-mode plumbing that used to live here is gone. It existed to tell
 * NavRail whether to render workspace items or project items, and to hide the
 * rail entirely on routes with no handle. AppShell needs none of that: the
 * workspace rail is always present and the project section appears when there
 * is a project in the URL.
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
