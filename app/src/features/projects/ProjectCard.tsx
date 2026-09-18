import { Link } from 'react-router'
import { FolderOpen } from 'lucide-react'
import { Card } from '@/ui/card'
import { StatusBadge } from '@/features/shared/StatusBadge'
import { relative, absolute } from '@/lib/formatDate'
import type { ProjectRow } from '@/shell/queries'

export function ProjectCard({ workspaceId, project }: { workspaceId: string; project: ProjectRow }) {
  return (
    <Card className="p-4 transition-colors hover:border-[--color-border-strong]">
      <Link
        to={`/workspace/${workspaceId}/project/${project.id}/overview`}
        className="flex flex-col gap-2 outline-none"
      >
        <div className="flex items-start justify-between gap-2">
          <div className="flex items-center gap-2 min-w-0">
            <FolderOpen className="h-4 w-4 text-[--color-text-muted] shrink-0" />
            <span className="truncate text-sm font-semibold text-[--color-text]">{project.name}</span>
          </div>
          <StatusBadge status={project.status} />
        </div>
        {project.description && (
          <p className="line-clamp-2 text-xs text-[--color-text-muted]">{project.description}</p>
        )}
        <div className="mt-1 flex items-center gap-2 text-xs text-[--color-text-subtle]">
          {project.code && <span className="font-mono">{project.code}</span>}
          {project.code && <span aria-hidden>·</span>}
          <span title={absolute(project.updated_at)}>updated {relative(project.updated_at)}</span>
        </div>
      </Link>
    </Card>
  )
}
