import { Navigate, Outlet, useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { useProject } from '@/shell/queries'
import { useProjectCapabilities } from '@/lib/capabilities'
import { AccessDeniedPage } from '@/shell/AccessDenied'

/**
 * Loads the project + capability map by URL params. Gates all inner routes on:
 *   1. project actually exists AND the URL's workspace matches its workspace
 *   2. caller has `project.view` (the entry-level capability)
 */
export function ProjectLayout() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()

  const project = useProject(proj_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')

  if (project.isLoading || caps.isLoading) return <LoadingPage />
  if (project.isError || !project.data) return <Navigate to={`/workspace/${ws_id}/projects`} replace />

  // Workspace mismatch (e.g. someone hand-typed a wrong ws_id for a real project id)
  if (project.data.workspace_id !== ws_id) {
    return (
      <Navigate to={`/workspace/${project.data.workspace_id}/project/${proj_id}/overview`} replace />
    )
  }

  if (!caps.data?.['project.view']) {
    return <AccessDeniedPage capability="project.view" />
  }

  return <Outlet />
}

ProjectLayout.handle = { navMode: 'project' as const }
