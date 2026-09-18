import * as React from 'react'
import { Link, useNavigate, useParams } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { MoreVertical, Pencil, Archive, Layers } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/ui/card'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { StatusBadge } from '@/features/shared/StatusBadge'
import { supabase } from '@/lib/supabase'
import { qk, type AssetFilters } from '@/lib/queryKeys'
import { useProject } from '@/shell/queries'
import { useAssets } from '@/features/designs/queries'
import { useProjectCapabilities } from '@/lib/capabilities'
import { humanizeError } from '@/features/shared/errors'
import { EditProjectDialog } from './EditProjectDialog'
import { relative, absolute } from '@/lib/formatDate'

export const ProjectOverviewHandle = { crumb: 'Overview' }

const EMPTY_FILTERS: AssetFilters = { collection: null, discipline: null, search: '' }

export function ProjectOverviewScreen() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const project = useProject(proj_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const assets = useAssets(proj_id, EMPTY_FILTERS)
  const [editOpen, setEditOpen] = React.useState(false)

  const archive = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('projects')
        .update({ status: 'archived', archived_at: new Date().toISOString() })
        .eq('id', proj_id as string)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Project archived')
      qc.invalidateQueries({ queryKey: qk.project(proj_id as string) })
      qc.invalidateQueries({ queryKey: qk.projects(ws_id as string) })
      navigate(`/workspace/${ws_id}/projects`)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  if (project.isLoading) return <LoadingPage />
  if (!project.data || !proj_id || !ws_id) {
    return (
      <div className="p-8">
        <EmptyState title="Project not found" />
      </div>
    )
  }

  const p = project.data
  const activeAssets = (assets.data ?? []).slice(0, 6)
  const canEdit = Boolean(caps.data?.['project.edit'])
  const canArchive = Boolean(caps.data?.['project.archive'])

  return (
    <div className="mx-auto max-w-4xl space-y-6 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <div className="flex items-center gap-2">
            <h1 className="truncate text-xl font-semibold">{p.name}</h1>
            <StatusBadge status={p.status} />
          </div>
          {p.description && <p className="text-sm text-[--color-text-muted]">{p.description}</p>}
          <div className="flex items-center gap-2 text-xs text-[--color-text-subtle]">
            {p.code && <span className="font-mono">{p.code}</span>}
            {p.code && <span aria-hidden>·</span>}
            <span title={absolute(p.updated_at)}>updated {relative(p.updated_at)}</span>
          </div>
        </div>
        {(canEdit || canArchive) && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" aria-label="Project actions">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              {canEdit && (
                <DropdownMenuItem onSelect={() => setEditOpen(true)}>
                  <Pencil className="h-4 w-4" />
                  Edit project
                </DropdownMenuItem>
              )}
              {canArchive && (
                <DropdownMenuItem
                  onSelect={() => {
                    if (window.confirm('Archive this project? It will be hidden from the projects list.')) {
                      archive.mutate()
                    }
                  }}
                  className="text-[--color-danger]"
                >
                  <Archive className="h-4 w-4" />
                  Archive project
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Recent design assets</CardTitle>
          </CardHeader>
          <CardContent>
            {assets.isLoading ? (
              <p className="text-sm text-[--color-text-muted]">Loading…</p>
            ) : activeAssets.length === 0 ? (
              <EmptyState
                icon={<Layers className="h-6 w-6" />}
                title="No design assets yet"
                description="Head to Designs to create your first asset."
                action={
                  <Button asChild size="sm" variant="secondary">
                    <Link to={`/workspace/${ws_id}/project/${proj_id}/designs`}>Go to Designs</Link>
                  </Button>
                }
              />
            ) : (
              <ul className="space-y-1.5">
                {activeAssets.map((a) => (
                  <li key={a.id}>
                    <Link
                      to={`/workspace/${ws_id}/project/${proj_id}/asset/${a.id}`}
                      className="flex items-center justify-between rounded-[--radius-sm] px-2 py-1.5 text-sm hover:bg-[--color-surface-2]"
                    >
                      <span className="truncate">{a.name}</span>
                      <span
                        className="ml-2 shrink-0 text-xs text-[--color-text-subtle]"
                        title={absolute(a.updated_at)}
                      >
                        {relative(a.updated_at)}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Project</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Slug" value={<span className="font-mono">{p.slug}</span>} />
            <Row label="Code" value={p.code || <Muted>—</Muted>} />
            <Row label="Created" value={<span title={absolute(p.created_at)}>{relative(p.created_at)}</span>} />
            <Row
              label="Assets"
              value={
                <span>
                  {assets.data?.length ?? 0} total
                </span>
              }
            />
          </CardContent>
        </Card>
      </div>

      <EditProjectDialog project={p} open={editOpen} onOpenChange={setEditOpen} />
    </div>
  )
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-xs text-[--color-text-muted]">{label}</span>
      <span className="truncate">{value}</span>
    </div>
  )
}
function Muted({ children }: { children: React.ReactNode }) {
  return <span className="text-[--color-text-subtle]">{children}</span>
}
