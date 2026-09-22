import { Navigate } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { useSession } from '@/auth/SessionProvider'
import { useWorkspaces } from '@/shell/queries'
import { useAccessCheck } from '@/auth/useAccessCheck'
import { readLastWorkspace } from '@/shell/WorkspaceSwitcher'

/**
 * The "/" route. Sends signed-in users to their last-visited workspace, then
 * to their only workspace if there's exactly one, then to the picker if 0 or
 * >1. Signed-out users bounce to /signin via AuthGate below this route.
 *
 * Before any of that: an account with no projects it can open and no admin
 * role anywhere goes to /no-access. Otherwise it lands on a workspace with an
 * empty project list, which reads as a broken product rather than a
 * permissions state. See auth/useAccessCheck.
 */
export function RootRedirect() {
  const { session, isLoading: sessionLoading } = useSession()
  const { data, isLoading } = useWorkspaces()
  const access = useAccessCheck()

  if (sessionLoading) return <LoadingPage />
  if (!session) return <Navigate to="/signin" replace />
  if (isLoading || access.isLoading) return <LoadingPage />
  if (access.data && !access.data.hasAccess) return <Navigate to="/no-access" replace />

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
