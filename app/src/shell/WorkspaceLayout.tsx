import { Navigate, Outlet, useLocation, useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { useWorkspace } from '@/shell/queries'
import {useWorkspaceAccess} from '@/lib/capabilities'
import {WorkspaceNavigation} from './ContextNavigation'
import { persistLastWorkspace } from '@/shell/WorkspaceSwitcher'
import * as React from 'react'

/**
 * Loads the workspace by URL param and gates any inner route on its presence
 * (workspaces the caller can't see resolve to null under RLS and bounce to /).
 */
export function WorkspaceLayout() {
  const { ws_id } = useParams<{ ws_id: string }>()
  const {pathname}=useLocation()
  const access=useWorkspaceAccess(ws_id)
  const { data, isLoading, isError } = useWorkspace(ws_id)

  React.useEffect(() => {
    if (ws_id && data) persistLastWorkspace(ws_id)
  }, [ws_id, data])

  if (isLoading) return <LoadingPage />
  if (isError || !data) return <Navigate to="/dashboard" replace />

  const project=pathname.startsWith(`/workspace/${ws_id}/project/`),inbox=pathname===`/workspace/${ws_id}/inbox`
  return <>{!project&&!inbox&&<WorkspaceNavigation workspaceId={ws_id!} name={data.name} canManage={Boolean(access.data?.['workspace.manage'])} canSeeTeam={Boolean(access.data?.['member.invite']||access.data?.['workspace.manage'])}/>}<Outlet/></>
}

WorkspaceLayout.handle = { navMode: 'workspace' as const }
