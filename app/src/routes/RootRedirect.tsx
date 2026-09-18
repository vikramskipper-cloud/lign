import { Navigate } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { useSession } from '@/auth/SessionProvider'
import { useWorkspaces } from '@/shell/queries'
import { readLastWorkspace } from '@/shell/WorkspaceSwitcher'

/**
 * The "/" route. Sends signed-in users to their last-visited workspace, then
 * to their only workspace if there's exactly one, then to the picker if 0 or
 * >1. Signed-out users bounce to /signin via AuthGate below this route.
 */
export function RootRedirect() {
  const { session, isLoading: sessionLoading } = useSession()
  const { data, isLoading } = useWorkspaces()

  if (sessionLoading) return <LoadingPage />
  if (!session) return <Navigate to="/signin" replace />
  if (isLoading) return <LoadingPage />

  const last = readLastWorkspace()
  const workspaces = data ?? []

  if (last && workspaces.some((w) => w.id === last)) {
    return <Navigate to={`/workspace/${last}/projects`} replace />
  }
  if (workspaces.length === 1) {
    return <Navigate to={`/workspace/${workspaces[0]!.id}/projects`} replace />
  }
  return <Navigate to="/workspace-picker" replace />
}
