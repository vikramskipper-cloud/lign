import * as React from 'react'
import { useParams } from 'react-router'
import { Plus, FolderOpen } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import { useProjects } from '@/shell/queries'
import { useWorkspaceAccess } from '@/lib/capabilities'
import { ProjectCard } from './ProjectCard'
import { NewProjectDialog } from './NewProjectDialog'

export const ProjectListHandle = { crumb: 'Projects' }

export function ProjectListScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  const { data, isLoading, isError } = useProjects(ws_id)
  const access = useWorkspaceAccess(ws_id)
  const [dialogOpen, setDialogOpen] = React.useState(false)

  // Hidden, not disabled: a control you can see but never use reads as a
  // broken feature. create_project_full enforces the same key server-side.
  const canCreate = Boolean(access.data?.['workspace.manage'])

  if (isLoading) return <LoadingPage />
  if (isError || !ws_id) {
    return (
      <div className="p-8">
        <EmptyState title="Couldn't load projects" description="Try again in a moment." />
      </div>
    )
  }

  const projects = data ?? []

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Projects</h1>
          <p className="text-sm text-[--color-text-muted]">
            {projects.length} {projects.length === 1 ? 'project' : 'projects'}
          </p>
        </div>
        {canCreate && (
          <Button size="sm" onClick={() => setDialogOpen(true)}>
            <Plus className="mr-1 h-4 w-4" />
            New project
          </Button>
        )}
      </div>

      {projects.length === 0 ? (
        <EmptyState
          icon={<FolderOpen className="h-8 w-8" />}
          title="No projects yet"
          description={
            canCreate
              ? 'Create your first project to start organizing designs.'
              : 'Nothing here yet. A workspace admin can create the first project.'
          }
          action={
            canCreate ? (
              <Button size="sm" onClick={() => setDialogOpen(true)}>
                <Plus className="mr-1 h-4 w-4" />
                New project
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {projects.map((p) => (
            <ProjectCard key={p.id} workspaceId={ws_id} project={p} />
          ))}
        </div>
      )}

      {canCreate && (
        <NewProjectDialog workspaceId={ws_id} open={dialogOpen} onOpenChange={setDialogOpen} />
      )}
    </div>
  )
}
