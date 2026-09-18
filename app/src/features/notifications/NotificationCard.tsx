import { Check, Archive, X, Link as LinkIcon } from 'lucide-react'

function formatRelative(iso: string): string {
  const then = new Date(iso).getTime()
  const now = Date.now()
  const diff = Math.max(0, now - then)
  const s = Math.floor(diff / 1000)
  if (s < 60) return 'just now'
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.floor(h / 24)
  if (d < 7) return `${d}d ago`
  const w = Math.floor(d / 7)
  if (w < 5) return `${w}w ago`
  return new Date(iso).toLocaleDateString()
}
import { cn } from '@/lib/cn'
import { Button } from '@/ui/button'
import { Badge } from '@/ui/badge'
import type { Notification, NotificationPriority } from './types'
import { useCopyLink } from '@/features/comments/useCopyLink'

interface Props {
  notification: Notification
  onOpen?: () => void
  onMarkRead?: () => void
  onDismiss?: () => void
  onArchive?: () => void
  compact?: boolean
}

const PRIORITY_LABEL: Record<NotificationPriority, string> = {
  critical: 'Critical',
  high: 'High',
  medium: 'Medium',
  low: 'Low',
  informational: 'Info',
}

const PRIORITY_TONE: Record<NotificationPriority, string> = {
  critical: 'bg-[--color-state-blocked]/15 text-[--color-state-blocked]',
  high: 'bg-[--color-state-attention]/15 text-[--color-state-attention]',
  medium: 'bg-[--color-state-neutral]/15 text-[--color-state-neutral]',
  low: 'bg-[--color-surface-2] text-[--color-text-muted]',
  informational: 'bg-[--color-surface-2] text-[--color-text-muted]',
}

export function NotificationCard({
  notification,
  onOpen,
  onMarkRead,
  onDismiss,
  onArchive,
  compact = false,
}: Props) {
  const unread = notification.read_at == null
  const copy = useCopyLink()
  const relative = formatRelative(notification.created_at)

  return (
    <div
      className={cn(
        'group relative flex gap-3 rounded-[--radius-md] border border-[--color-border] p-3 transition-colors',
        unread ? 'bg-[--color-surface]' : 'bg-[--color-surface-2]',
        'hover:border-[--color-border-strong]',
      )}
    >
      {unread && (
        <span
          aria-hidden
          className="absolute left-1 top-4 h-2 w-2 rounded-full bg-[--color-brand]"
        />
      )}
      <div className="flex-1 min-w-0 pl-3">
        <button
          type="button"
          onClick={onOpen}
          className="block w-full text-left"
        >
          <div className="flex items-center gap-2 text-xs text-[--color-text-muted]">
            <span
              className={cn(
                'inline-flex items-center rounded-full px-2 py-0.5 text-[0.6875rem] font-medium',
                PRIORITY_TONE[notification.priority],
              )}
            >
              {PRIORITY_LABEL[notification.priority]}
            </span>
            <span className="truncate">{notification.payload?.actor_display_name ?? 'System'}</span>
            <span aria-hidden>•</span>
            <span className="whitespace-nowrap">{relative}</span>
          </div>
          <div
            className={cn(
              'mt-1 truncate font-medium',
              unread ? 'text-[--color-text]' : 'text-[--color-text-muted]',
            )}
          >
            {notification.subject_label ?? notification.notification_type}
          </div>
          {!compact && (
            <div className="mt-0.5 line-clamp-2 text-sm text-[--color-text-muted]">
              {notification.payload?.preview_snippet ?? notification.notification_type}
            </div>
          )}
        </button>
        <div className="mt-2 flex items-center gap-1">
          <Badge variant="outline" className="text-[0.6875rem]">
            {notification.category.replace(/_/g, ' ')}
          </Badge>
        </div>
      </div>
      <div className="flex flex-col items-end gap-1 opacity-0 transition-opacity group-hover:opacity-100">
        {unread && onMarkRead && (
          <Button variant="ghost" size="icon" aria-label="Mark read" onClick={onMarkRead}>
            <Check className="h-3.5 w-3.5" />
          </Button>
        )}
        {onDismiss && (
          <Button variant="ghost" size="icon" aria-label="Dismiss" onClick={onDismiss}>
            <X className="h-3.5 w-3.5" />
          </Button>
        )}
        {onArchive && (
          <Button variant="ghost" size="icon" aria-label="Archive" onClick={onArchive}>
            <Archive className="h-3.5 w-3.5" />
          </Button>
        )}
        <Button
          variant="ghost"
          size="icon"
          aria-label="Copy link"
          onClick={() => copy('notification', notification.id)}
        >
          <LinkIcon className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  )
}
