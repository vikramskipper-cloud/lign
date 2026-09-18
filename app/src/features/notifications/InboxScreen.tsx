import * as React from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router'
import { Inbox as InboxIcon, CheckCheck } from 'lucide-react'
import { Button } from '@/ui/button'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/ui/tabs'
import { Skeleton } from '@/ui/skeleton'
import { EmptyState } from '@/ui/empty-state'
import { cn } from '@/lib/cn'
import { NotificationCard } from './NotificationCard'
import { NotificationFilterBar } from './NotificationFilterBar'
import { useNotificationsInbox } from './queries'
import {
  useArchiveNotification,
  useDismissNotification,
  useMarkAllNotificationsRead,
  useMarkNotificationRead,
} from './mutations'
import type {
  InboxFilters,
  InboxTab,
  Notification,
  NotificationCategory,
  NotificationPriority,
  SourceModule,
} from './types'

export const InboxHandle = { crumb: 'Inbox' }

const TABS: { value: InboxTab; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'unread', label: 'Unread' },
  { value: 'mentions', label: 'Mentions' },
  { value: 'assigned', label: 'Assigned' },
  { value: 'governance', label: 'Governance' },
  { value: 'archived', label: 'Archived' },
]

const EMPTY_COPY: Record<InboxTab, string> = {
  all: "You're all caught up — no notifications yet in this workspace.",
  unread: "Nothing unread. You've handled everything.",
  mentions: 'You have not been mentioned in any comments yet.',
  assigned: 'Nothing is currently waiting on you. Good work.',
  governance: 'No governance activity in the last retention window.',
  archived: 'You have not archived any notifications yet.',
}

function parseTab(v: string | null): InboxTab {
  const t = (v as InboxTab) || 'all'
  return TABS.some((tt) => tt.value === t) ? t : 'all'
}

function csv<T extends string>(v: string | null): T[] | undefined {
  if (!v) return undefined
  const parts = v
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean) as T[]
  return parts.length === 0 ? undefined : parts
}

/**
 * APP 010 §12 / §16: Inbox screen at /workspace/:ws_id/inbox. Six tabs +
 * filter bar + cursor pagination.
 */
export function InboxScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  const [params, setParams] = useSearchParams()
  const nav = useNavigate()

  const tab = parseTab(params.get('tab'))
  const highlight = params.get('highlight')

  const filters: InboxFilters = React.useMemo(
    () => ({
      category: csv<NotificationCategory>(params.get('category')),
      priority: csv<NotificationPriority>(params.get('priority')),
      source: csv<SourceModule>(params.get('source')),
      dateFrom: params.get('date_from'),
      dateTo: params.get('date_to'),
      cursor: null,
      limit: 50,
    }),
    [params],
  )

  const q = useNotificationsInbox(ws_id, tab, filters)
  const markRead = useMarkNotificationRead(ws_id ?? '')
  const dismiss = useDismissNotification(ws_id ?? '')
  const archive = useArchiveNotification(ws_id ?? '')
  const markAll = useMarkAllNotificationsRead(ws_id ?? '')

  const setTab = (next: InboxTab) => {
    const p = new URLSearchParams(params)
    p.set('tab', next)
    setParams(p, { replace: true })
  }

  const applyFilters = (next: InboxFilters) => {
    const p = new URLSearchParams(params)
    const setOrDel = (key: string, arr?: string[]) => {
      if (!arr || arr.length === 0) p.delete(key)
      else p.set(key, arr.join(','))
    }
    setOrDel('category', next.category)
    setOrDel('priority', next.priority)
    setOrDel('source', next.source)
    if (next.dateFrom) p.set('date_from', next.dateFrom)
    else p.delete('date_from')
    if (next.dateTo) p.set('date_to', next.dateTo)
    else p.delete('date_to')
    setParams(p, { replace: true })
  }

  const openNotification = (n: Notification) => {
    markRead.mutate(n.id)
    const dl = n.payload?.deep_link
    if (dl?.kind && dl?.id) nav(`/deep/${dl.kind}/${dl.id}`)
  }

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center justify-between border-b border-[--color-border] bg-[--color-surface] px-4 py-3">
        <div className="flex items-center gap-2">
          <InboxIcon className="h-4 w-4 text-[--color-text-muted]" />
          <h1 className="text-base font-semibold">Inbox</h1>
        </div>
        <div className="flex items-center gap-2 text-xs text-[--color-text-muted]">
          <span>{q.data?.facets.unread_count ?? 0} unread</span>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => markAll.mutate(null)}
            disabled={markAll.isPending || (q.data?.facets.unread_count ?? 0) === 0}
          >
            <CheckCheck className="mr-1 h-3.5 w-3.5" /> Mark all read
          </Button>
        </div>
      </header>

      <Tabs value={tab} onValueChange={(v) => setTab(v as InboxTab)}>
        <TabsList className="mx-4 mt-3">
          {TABS.map((t) => (
            <TabsTrigger key={t.value} value={t.value}>
              {t.label}
            </TabsTrigger>
          ))}
        </TabsList>

        <NotificationFilterBar filters={filters} onChange={applyFilters} />

        <TabsContent value={tab} className="mt-0 flex-1">
          <div className="mx-auto max-w-3xl space-y-2 p-4">
            {q.isLoading && (
              <>
                {Array.from({ length: 8 }).map((_, i) => (
                  <Skeleton key={i} className="h-20 w-full rounded-[--radius-md]" />
                ))}
              </>
            )}
            {q.isError && (
              <div className="rounded-[--radius-md] border border-[--color-border] p-6 text-center text-sm">
                Couldn't load your notifications.{' '}
                <button
                  type="button"
                  onClick={() => q.refetch()}
                  className="text-[--color-brand] hover:underline"
                >
                  Retry
                </button>
              </div>
            )}
            {!q.isLoading && !q.isError && (q.data?.rows.length ?? 0) === 0 && (
              <EmptyState title="No notifications" description={EMPTY_COPY[tab]} />
            )}
            {!q.isLoading &&
              !q.isError &&
              q.data?.rows.map((n) => (
                <div
                  key={n.id}
                  id={`notification-${n.id}`}
                  className={cn(
                    'transition-shadow',
                    highlight === n.id && 'ring-2 ring-[--color-brand]',
                  )}
                >
                  <NotificationCard
                    notification={n}
                    onOpen={() => openNotification(n)}
                    onMarkRead={
                      n.read_at ? undefined : () => markRead.mutate(n.id)
                    }
                    onDismiss={
                      n.dismissed_at ? undefined : () => dismiss.mutate(n.id)
                    }
                    onArchive={
                      n.archived_at ? undefined : () => archive.mutate(n.id)
                    }
                  />
                </div>
              ))}
          </div>
        </TabsContent>
      </Tabs>
    </div>
  )
}
