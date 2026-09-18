import { Navigate, Outlet, useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { useWorkspace } from '@/shell/queries'
import { persistLastWorkspace } from '@/shell/WorkspaceSwitcher'
import * as React from 'react'

/**
 * Loads the workspace by URL param and gates any inner route on its presence
 * (workspaces the caller can't see resolve to null under RLS and bounce to /).
 */
export function WorkspaceLayout() {
  const { ws_id } = useParams<{ ws_id: string }>()
  const { data, isLoading, isError } = useWorkspace(ws_id)

  React.useEffect(() => {
    if (ws_id && data) persistLastWorkspace(ws_id)
  }, [ws_id, data])

  if (isLoading) return <LoadingPage />
  if (isError || !data) return <Navigate to="/" replace />

  return <Outlet />
}

WorkspaceLayout.handle = { navMode: 'workspace' as const }
