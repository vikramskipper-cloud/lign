import * as React from 'react'
import { Link, useMatches, useParams } from 'react-router'
import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/cn'
import { useWorkspace, useProject } from '@/shell/queries'
import { WorkspaceSwitcher } from '@/shell/WorkspaceSwitcher'
import { ProjectBreadcrumbSwitcher } from '@/shell/ProjectBreadcrumbSwitcher'

interface RouteHandle {
  crumb?: string
}

/**
 * Compound breadcrumb:
 *   [WorkspaceSwitcher]  ›  [ProjectBreadcrumbSwitcher]  ›  Page name
 * The page-name segment is contributed by the last matched route via its
 * handle.crumb (React Router v7 handle pattern). Missing handles are skipped.
 */
export function Breadcrumb() {
  const { ws_id, proj_id } = useParams()
  const matches = useMatches()

  const workspace = useWorkspace(ws_id)
  const project = useProject(proj_id)

  const pageCrumb = React.useMemo(() => {
    // Take the LAST match that provides a crumb.
    for (let i = matches.length - 1; i >= 0; i--) {
      const handle = matches[i]?.handle as RouteHandle | undefined
      if (handle?.crumb) return handle.crumb
    }
    return undefined
  }, [matches])

  return (
    <div className="flex items-center gap-1 text-sm text-[--color-text-muted]">
      {ws_id && (
        <>
          <WorkspaceSwitcher currentWorkspaceId={ws_id} currentName={workspace.data?.name} />
          {proj_id && <BreadcrumbSep />}
        </>
      )}
      {ws_id && proj_id && (
        <>
          <ProjectBreadcrumbSwitcher
            workspaceId={ws_id}
            currentProjectId={proj_id}
            currentName={project.data?.name}
          />
          {pageCrumb && <BreadcrumbSep />}
        </>
      )}
      {pageCrumb && (
        <span className={cn('truncate text-[--color-text]')}>
          {pageCrumb}
        </span>
      )}
      {/* Ensure the breadcrumb has a home link even without segments */}
      {!ws_id && (
        <Link to="/dashboard" className="text-sm font-medium text-[--color-text]">
          Lign
        </Link>
      )}
    </div>
  )
}

function BreadcrumbSep() {
  return <ChevronRight className="h-4 w-4 shrink-0 text-[--color-text-subtle]" />
}
