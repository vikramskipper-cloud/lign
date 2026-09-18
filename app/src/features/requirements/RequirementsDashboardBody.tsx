import * as React from 'react'
import { useSearchParams } from 'react-router'
import { ListChecks, Plus, Search } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { Skeleton } from '@/ui/skeleton'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { RequirementFilterBar } from './RequirementFilterBar'
import { RequirementCard } from './RequirementCard'
import { CreateRequirementDialog } from './CreateRequirementDialog'
import {
  useRequirementsDashboard,
  type RequirementCategoryKind,
  type RequirementPriority,
  type RequirementSourceKind,
  type RequirementStatus,
  type RequirementsDashboardView,
} from './queries'
import { useProjectCapabilities } from '@/lib/capabilities'
import { useWorkspaceHotkeys } from '@/features/design-workspace/useWorkspaceHotkeys'

interface Props {
  workspaceId: string
  projectId: string | null
  heading: string
  subheading?: React.ReactNode
  metricsSlot?: React.ReactNode
}

const ALL_VIEWS: RequirementsDashboardView[] = [
  'all_active',
  'assigned_to_me',
  'recently_updated',
  'by_status',
  'by_priority',
  'by_source',
  'needs_assessment',
  'overdue_critical',
  'bookmarks',
  'archived',
  'superseded',
  'compliance',
  'all',
]

export function RequirementsDashboardBody({
  workspaceId,
  projectId,
  heading,
  subheading,
  metricsSlot,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const rawView = searchParams.get('view') as RequirementsDashboardView | null
  const view: RequirementsDashboardView = ALL_VIEWS.includes(
    rawView as RequirementsDashboardView,
  )
    ? (rawView as RequirementsDashboardView)
    : 'all_active'
  const statusFilter = (searchParams
    .get('status')
    ?.split(',')
    .filter(Boolean) ?? []) as RequirementStatus[]
  const priorityFilter = (searchParams
    .get('priority')
    ?.split(',')
    .filter(Boolean) ?? []) as RequirementPriority[]
  const sourceFilter = (searchParams
    .get('source')
    ?.split(',')
    .filter(Boolean) ?? []) as RequirementSourceKind[]
  const categoryFilter = (searchParams
    .get('category')
    ?.split(',')
    .filter(Boolean) ?? []) as RequirementCategoryKind[]
  const scopeFilter = searchParams.get('scope') as
    | 'project_wide'
    | 'asset_scoped'
    | null
  const searchTerm = searchParams.get('code') ?? ''
  const composeOpen = searchParams.get('compose') === '1'

  const [searchInput, setSearchInput] = React.useState(searchTerm)
  const searchInputRef = React.useRef<HTMLInputElement | null>(null)

  const setView = (v: RequirementsDashboardView) => {
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
    Boolean(projectId) && Boolean(caps.data?.['requirement.create'])

  useWorkspaceHotkeys({
    onNewRequirement: canCreate ? () => setComposeOpen(true) : undefined,
    onFocusRequirementSearch: () => searchInputRef.current?.focus(),
  })

  const q = useRequirementsDashboard(workspaceId, projectId, view, {
    status: statusFilter.length ? statusFilter : undefined,
    priority: priorityFilter.length ? priorityFilter : undefined,
    source: sourceFilter.length ? sourceFilter : undefined,
    category: categoryFilter.length ? categoryFilter : undefined,
    scope: scopeFilter,
    search: searchInput.trim() || undefined,
  })

  const rows = q.data?.rows ?? []

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
            New requirement
          </Button>
        )}
      </div>

      {metricsSlot}

      <div className="flex items-center gap-2">
        <RequirementFilterBar value={view} onChange={setView} />
        <div className="relative ml-auto max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-[--color-text-subtle]" />
          <Input
            ref={searchInputRef}
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder="Search code, title, description"
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
          title="Couldn't load requirements"
          action={
            <Button size="sm" variant="secondary" onClick={() => q.refetch()}>
              Retry
            </Button>
          }
        />
      ) : rows.length === 0 ? (
        <EmptyStateForView
          view={view}
          hasSearch={Boolean(searchInput.trim())}
          onClearSearch={() => setSearchInput('')}
        />
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {rows.map((r) => (
            <RequirementCard key={r.requirement_id} row={r} />
          ))}
        </div>
      )}

      {projectId && (
        <CreateRequirementDialog
          workspaceId={workspaceId}
          projectId={projectId}
          open={composeOpen}
          onOpenChange={setComposeOpen}
        />
      )}
    </div>
  )
}

function EmptyStateForView({
  view,
  hasSearch,
  onClearSearch,
}: {
  view: RequirementsDashboardView
  hasSearch: boolean
  onClearSearch: () => void
}) {
  if (hasSearch) {
    return (
      <EmptyState
        icon={<Search className="h-8 w-8" />}
        title="No requirements match your search"
        action={
          <Button size="sm" variant="secondary" onClick={onClearSearch}>
            Clear search
          </Button>
        }
      />
    )
  }
  const msg: Partial<
    Record<RequirementsDashboardView, { title: string; description?: string }>
  > = {
    all_active: { title: 'No requirements yet.', description: 'Create the first one.' },
    assigned_to_me: {
      title: "You're all caught up.",
      description: 'No requirements are assigned to you.',
    },
    recently_updated: { title: 'Nothing updated recently.' },
    by_status: { title: 'No requirements yet.' },
    by_priority: { title: 'No requirements yet.' },
    by_source: { title: 'No requirements yet.' },
    needs_assessment: { title: 'Everything applicable is assessed.' },
    overdue_critical: { title: 'No overdue critical requirements.' },
    bookmarks: { title: 'Bookmark requirements to find them fast.' },
    archived: { title: 'No archived requirements.' },
    superseded: { title: 'No superseded requirements.' },
    compliance: { title: 'No requirements to review.' },
    all: { title: 'No requirements yet.' },
  }
  const m = msg[view] ?? { title: 'No requirements' }
  return (
    <EmptyState
      icon={<ListChecks className="h-8 w-8" />}
      title={m.title}
      description={m.description}
    />
  )
}
