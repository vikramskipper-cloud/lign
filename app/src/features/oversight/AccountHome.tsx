import { Navigate } from 'react-router'
import { useMyOrganizations } from '@/shell/orgQueries'
import { useActiveWorkspaceId } from '@/shell/useActiveWorkspace'
import { useWorkspaces } from '@/shell/queries'
import { useWorkspaceAccess } from '@/lib/capabilities'
import { HomeScreen } from '@/features/home/HomeScreen'
import { FullPageLoader } from '@/ui/full-page-loader'

/** Owners land on studio oversight; workspace leads land on their workspace. */
export function AccountHome() {
  const { workspaceId } = useActiveWorkspaceId()
  const workspaces = useWorkspaces()
  const orgs = useMyOrganizations()
  const access = useWorkspaceAccess(workspaceId)
  if (workspaces.isLoading || orgs.isLoading || access.isLoading) return <FullPageLoader />
  const currentOrg = workspaces.data?.find((w) => w.id === workspaceId)?.organization_id
  const adminOrgs = (orgs.data ?? []).filter((o) => o.role === 'owner' || o.role === 'admin')
  const org = adminOrgs.find((o) => o.id === currentOrg) ?? adminOrgs[0]
  if (org) return <Navigate to={`/org/${org.id}/overview`} replace />
  if (workspaceId && access.data?.['workspace.manage']) return <Navigate to={`/workspace/${workspaceId}/overview`} replace />
  return <HomeScreen />
}
