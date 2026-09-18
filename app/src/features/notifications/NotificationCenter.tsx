import { Link, useNavigate } from 'react-router'
import { CheckCheck } from 'lucide-react'
import { Button } from '@/ui/button'
import { Skeleton } from '@/ui/skeleton'
import { useNotificationCenter } from './queries'
import {
  useMarkAllNotificationsRead,
  useMarkNotificationRead,
} from './mutations'
import { NotificationCard } from './NotificationCard'
import type { Notification } from './types'

interface Props {
  wsId: string
  onNavigate?: () => void
}

/**
 * APP 010 §13: Notification Center popover body. Renders top 15 unread
 * notifications for the workspace + "Mark all read" footer + "View all in Inbox".
 */
export function NotificationCenter({ wsId, onNavigate }: Props) {
  const nav = useNavigate()
  const q = useNotificationCenter(wsId)
  const markRead = useMarkNotificationRead(wsId)
  const markAll = useMarkAllNotificationsRead(wsId)

  const openNotification = (n: Notification) => {
    markRead.mutate(n.id)
    const dl = n.payload?.deep_link
    if (dl?.kind && dl?.id) {
      nav(`/deep/${dl.kind}/${dl.id}`)
    }
    onNavigate?.()
  }

  return (
    <div className="flex max-h-[80vh] w-[400px] max-w-[92vw] flex-col">
      <div className="flex items-center justify-between border-b border-[--color-border] px-3 py-2">
        <div className="text-sm font-semibold">Notifications</div>
        <Link
          to={`/workspace/${wsId}/inbox`}
          className="text-xs text-[--color-text-muted] hover:underline"
          onClick={onNavigate}
        >
          View all in Inbox
        </Link>
      </div>

      <div className="flex-1 overflow-y-auto p-2">
        {q.isLoading && (
          <div className="space-y-2">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-16 w-full rounded-[--radius-md]" />
            ))}
          </div>
        )}
        {q.isError && (
          <div className="p-4 text-center text-sm text-[--color-text-muted]">
            Couldn't load notifications.{' '}
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
          <div className="p-6 text-center text-sm text-[--color-text-muted]">
            You're up to date.
          </div>
        )}
        {!q.isLoading &&
          !q.isError &&
          q.data?.rows.map((n) => (
            <div key={n.id} className="mb-2 last:mb-0">
              <NotificationCard
                notification={n}
                compact
                onOpen={() => openNotification(n)}
              />
            </div>
          ))}

        {(q.data?.has_more ?? false) && (
          <Link
            to={`/workspace/${wsId}/inbox?tab=unread`}
            className="mt-2 block text-center text-xs text-[--color-text-muted] hover:underline"
            onClick={onNavigate}
          >
            More in Inbox
          </Link>
        )}
      </div>

      <div className="flex items-center justify-between border-t border-[--color-border] px-3 py-2">
        <span className="text-xs text-[--color-text-muted]">
          {q.data?.total_unread ?? 0} unread
        </span>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => markAll.mutate(null)}
          disabled={markAll.isPending || (q.data?.total_unread ?? 0) === 0}
        >
          <CheckCheck className="mr-1 h-3.5 w-3.5" /> Mark all read
        </Button>
      </div>
    </div>
  )
}
