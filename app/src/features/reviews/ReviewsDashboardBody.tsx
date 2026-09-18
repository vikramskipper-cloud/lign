import * as React from 'react'
import { useSearchParams } from 'react-router'
import { ClipboardCheck, Search } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { Skeleton } from '@/ui/skeleton'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { ReviewFilterBar } from './ReviewFilterBar'
import { ReviewCard } from './ReviewCard'
import { useReviewsDashboard, type DashboardView, type ReviewStatus } from './queries'

interface Props {
  workspaceId: string
  projectId: string | null
  heading: string
  subheading?: React.ReactNode
  metricsSlot?: React.ReactNode
}

const ALL_VIEWS: DashboardView[] = [
  'assigned_to_me',
  'waiting_on_others',
  'overdue',
  'completed',
  'recent',
  'bookmarks',
]

export function ReviewsDashboardBody({
  workspaceId,
  projectId,
  heading,
  subheading,
  metricsSlot,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const rawView = searchParams.get('view') as DashboardView | null
  const view: DashboardView = ALL_VIEWS.includes(rawView as DashboardView)
    ? (rawView as DashboardView)
    : 'assigned_to_me'
  const statusFilter = (searchParams.get('status')?.split(',').filter(Boolean) ??
    []) as ReviewStatus[]
  const [search, setSearch] = React.useState('')

  const setView = (v: DashboardView) => {
    const next = new URLSearchParams(searchParams)
    next.set('view', v)
    setSearchParams(next, { replace: true })
  }

  const q = useReviewsDashboard(workspaceId, projectId, view, {
    status: statusFilter.length ? statusFilter : undefined,
  })

  const rows = React.useMemo(() => {
    const src = q.data ?? []
    if (!search.trim()) return src
    const needle = search.trim().toLowerCase()
    return src.filter(
      (r) =>
        r.out_title.toLowerCase().includes(needle) ||
        (r.out_description && r.out_description.toLowerCase().includes(needle)),
    )
  }, [q.data, search])

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <h1 className="text-xl font-semibold">{heading}</h1>
          {subheading}
        </div>
      </div>

      {metricsSlot}

      <div className="flex items-center gap-2">
        <ReviewFilterBar value={view} onChange={setView} />
        <div className="relative ml-auto max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-[--color-text-subtle]" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search reviews"
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
          title="Couldn't load reviews"
          action={
            <Button size="sm" variant="secondary" onClick={() => q.refetch()}>
              Retry
            </Button>
          }
        />
      ) : rows.length === 0 ? (
        <EmptyStateForView view={view} onClearSearch={() => setSearch('')} hasSearch={!!search.trim()} />
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {rows.map((r) => (
            <ReviewCard key={r.out_id} row={r} />
          ))}
        </div>
      )}
    </div>
  )
}

function EmptyStateForView({
  view,
  onClearSearch,
  hasSearch,
}: {
  view: DashboardView
  onClearSearch: () => void
  hasSearch: boolean
}) {
  if (hasSearch) {
    return (
      <EmptyState
        icon={<Search className="h-8 w-8" />}
        title="No reviews match your search"
        action={
          <Button size="sm" variant="secondary" onClick={onClearSearch}>
            Clear search
          </Button>
        }
      />
    )
  }
  const msg: Record<DashboardView, { title: string; description?: string }> = {
    assigned_to_me: { title: "You're all caught up.", description: 'No reviews assigned to you right now.' },
    waiting_on_others: { title: 'No reviews you own are waiting.' },
    overdue: { title: 'Nothing overdue.' },
    completed: { title: 'No completed reviews yet.' },
    recent: { title: 'No reviews yet.', description: 'Start one from any design version.' },
    bookmarks: { title: 'Bookmark reviews to find them fast.' },
  }
  const m = msg[view]
  return <EmptyState icon={<ClipboardCheck className="h-8 w-8" />} title={m.title} description={m.description} />
}
