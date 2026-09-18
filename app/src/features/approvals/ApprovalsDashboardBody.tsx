import * as React from 'react'
import { useSearchParams } from 'react-router'
import { ShieldCheck, Search } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { Skeleton } from '@/ui/skeleton'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { ApprovalFilterBar } from './ApprovalFilterBar'
import { ApprovalCard } from './ApprovalCard'
import {
  useApprovalsDashboard,
  type ApprovalDashboardView,
  type ApprovalStatus,
  type ApprovalPolicy,
} from './queries'

interface Props {
  workspaceId: string
  projectId: string | null
  heading: string
  subheading?: React.ReactNode
  metricsSlot?: React.ReactNode
}

const ALL_VIEWS: ApprovalDashboardView[] = [
  'awaiting_me',
  'awaiting_others',
  'approved',
  'rejected',
  'expired_cancelled',
  'recent',
  'bookmarks',
]

export function ApprovalsDashboardBody({
  workspaceId,
  projectId,
  heading,
  subheading,
  metricsSlot,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const rawView = searchParams.get('view') as ApprovalDashboardView | null
  const view: ApprovalDashboardView = ALL_VIEWS.includes(rawView as ApprovalDashboardView)
    ? (rawView as ApprovalDashboardView)
    : 'awaiting_me'
  const statusFilter = (searchParams.get('status')?.split(',').filter(Boolean) ??
    []) as ApprovalStatus[]
  const policyFilter = (searchParams.get('policy')?.split(',').filter(Boolean) ??
    []) as ApprovalPolicy[]
  const [search, setSearch] = React.useState('')

  const setView = (v: ApprovalDashboardView) => {
    const next = new URLSearchParams(searchParams)
    next.set('view', v)
    setSearchParams(next, { replace: true })
  }

  const q = useApprovalsDashboard(workspaceId, projectId, view, {
    status: statusFilter.length ? statusFilter : undefined,
    policy: policyFilter.length ? policyFilter : undefined,
  })

  const rows = React.useMemo(() => {
    const src = q.data ?? []
    if (!search.trim()) return src
    const needle = search.trim().toLowerCase()
    return src.filter(
      (r) =>
        (r.out_title?.toLowerCase().includes(needle) ?? false) ||
        (r.out_description?.toLowerCase().includes(needle) ?? false),
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
        <ApprovalFilterBar value={view} onChange={setView} />
        <div className="relative ml-auto max-w-xs flex-1">
          <Search className="pointer-events-none absolute left-2 top-1/2 h-4 w-4 -translate-y-1/2 text-[--color-text-subtle]" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search approvals"
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
          title="Couldn't load approvals"
          action={
            <Button size="sm" variant="secondary" onClick={() => q.refetch()}>
              Retry
            </Button>
          }
        />
      ) : rows.length === 0 ? (
        <EmptyStateForView
          view={view}
          onClearSearch={() => setSearch('')}
          hasSearch={!!search.trim()}
        />
      ) : (
        <div className="grid grid-cols-1 gap-3">
          {rows.map((r) => (
            <ApprovalCard key={r.out_id} row={r} />
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
  view: ApprovalDashboardView
  onClearSearch: () => void
  hasSearch: boolean
}) {
  if (hasSearch) {
    return (
      <EmptyState
        icon={<Search className="h-8 w-8" />}
        title="No approvals match your search"
        action={
          <Button size="sm" variant="secondary" onClick={onClearSearch}>
            Clear search
          </Button>
        }
      />
    )
  }
  const msg: Record<ApprovalDashboardView, { title: string; description?: string }> = {
    awaiting_me: {
      title: "You're all caught up.",
      description: 'No approvals are awaiting your decision.',
    },
    awaiting_others: { title: 'No approvals you requested are pending.' },
    approved: { title: 'No approved approvals yet.' },
    rejected: { title: 'No rejected approvals.' },
    expired_cancelled: { title: 'Nothing expired or cancelled.' },
    recent: {
      title: 'No approvals yet.',
      description: 'Start one from any published design version.',
    },
    bookmarks: { title: 'Bookmark approvals to find them fast.' },
  }
  const m = msg[view]
  return (
    <EmptyState icon={<ShieldCheck className="h-8 w-8" />} title={m.title} description={m.description} />
  )
}
