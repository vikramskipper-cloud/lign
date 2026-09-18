import * as React from 'react'
import { useSearchParams } from 'react-router'
import { Package, Plus, Search } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { Skeleton } from '@/ui/skeleton'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { ReleaseFilterBar } from './ReleaseFilterBar'
import { ReleaseCard } from './ReleaseCard'
import { CreateReleaseDialog } from './CreateReleaseDialog'
import {
  useReleasesDashboard,
  type ReleasesDashboardView,
} from './queries'
import { useProjectCapabilities } from '@/lib/capabilities'

interface Props {
  workspaceId: string
  projectId: string | null
  heading: string
  subheading?: React.ReactNode
  metricsSlot?: React.ReactNode
}

const ALL_VIEWS: ReleasesDashboardView[] = [
  'all',
  'draft',
  'released',
  'withdrawn',
  'discarded',
  'published_by_me',
]

export function ReleasesDashboardBody({
  workspaceId,
  projectId,
  heading,
  subheading,
  metricsSlot,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const rawView = searchParams.get('view') as ReleasesDashboardView | null
  const view: ReleasesDashboardView = ALL_VIEWS.includes(
    rawView as ReleasesDashboardView,
  )
    ? (rawView as ReleasesDashboardView)
    : 'all'
  const searchTerm = searchParams.get('q') ?? ''
  const composeOpen = searchParams.get('compose') === '1'
  const [searchInput, setSearchInput] = React.useState(searchTerm)

  const setView = (v: ReleasesDashboardView) => {
    const next = new URLSearchParams(searchParams)
    next.set('view', v)
    setSearchParams(next, { replace: true })
  }
  const setComposeOpen = (open: boolean) => {
    const next = new URLSearchParams(searchParams)
    if (open) next.set('compose', '1')
    else next.delete('compose')
    setSearchParams(next, { replace: true })
  }

  const caps = useProjectCapabilities(projectId ?? '', workspaceId)
  const canCreate =
    Boolean(projectId) && Boolean(caps.data?.['release.create'])

  const q = useReleasesDashboard(workspaceId, projectId, view, {
    search: searchInput.trim() || undefined,
  })
  const rows = q.data ?? []

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <h1 className="text-xl font-semibold">{heading}</h1>
          {subheading}
        </div>
        {canCreate && projectId && (
          <Button size="sm" onClick={() => setComposeOpen(true)}>
            <Plus className="mr-1 h-3.5 w-3.5" />
            New release
          </Button>
        )}
      </div>

      {metricsSlot}

      <div className="flex items-center gap-2">
        <ReleaseFilterBar value={view} onChange={setView} />
        <div className="relative ml-auto max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-[--color-text-subtle]" />
          <Input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search name or code"
            className="pl-8"
          />
        </div>
      </div>

      {q.isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-24 w-full" />
        </div>
      ) : q.isError ? (
        <EmptyState
          title="Couldn't load releases"
          action={
            <Button size="sm" variant="secondary" onClick={() => q.refetch()}>
              Retry
            </Button>
          }
        />
      ) : rows.length === 0 ? (
        <EmptyState
          icon={<Package className="h-8 w-8" />}
          title="No releases match this view."
          description="Try a different view or clear your search."
        />
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {rows.map((r) => (
            <ReleaseCard key={r.out_release_id} row={r} />
          ))}
        </div>
      )}

      {projectId && (
        <CreateReleaseDialog
          workspaceId={workspaceId}
          projectId={projectId}
          open={composeOpen}
          onOpenChange={setComposeOpen}
        />
      )}
    </div>
  )
}
