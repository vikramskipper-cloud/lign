import * as React from 'react'
import { Bell } from 'lucide-react'
import { useParams } from 'react-router'
import * as DropdownMenu from '@radix-ui/react-dropdown-menu'
import { Button } from '@/ui/button'
import { cn } from '@/lib/cn'
import { NotificationBadge } from './NotificationBadge'
import { NotificationCenter } from './NotificationCenter'
import { useNotificationBadgeCount } from './queries'

/**
 * APP 010 §14.1 / §13: bell icon + unread badge in the top bar.
 * Click toggles the Notification Center popover. Hotkey N (workspace scope).
 */
export function NotificationBell() {
  const { ws_id } = useParams<{ ws_id?: string }>()
  const [open, setOpen] = React.useState(false)
  const q = useNotificationBadgeCount(ws_id)
  const count = q.data?.total_unread ?? 0
  const critical = q.data?.has_critical ?? false

  // Hotkey N toggles popover; Shift+N is handled in useWorkspaceHotkeys → route change.
  React.useEffect(() => {
    if (!ws_id) return
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return
      const t = e.target
      if (t instanceof HTMLElement) {
        const tag = t.tagName
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
        if (t.isContentEditable) return
      }
      if (e.key === 'n' || e.key === 'N') {
        e.preventDefault()
        setOpen((v) => !v)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [ws_id])

  if (!ws_id) {
    return (
      <Button variant="ghost" size="icon" aria-label="Notifications" disabled>
        <Bell className="h-4 w-4" />
      </Button>
    )
  }

  return (
    <DropdownMenu.Root open={open} onOpenChange={setOpen}>
      <DropdownMenu.Trigger asChild>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Notifications (${count} unread)`}
          className="relative"
        >
          <Bell className={cn('h-4 w-4', critical && 'text-[--color-state-blocked]')} />
          {count > 0 && (
            <span className="absolute -right-0.5 -top-0.5">
              <NotificationBadge count={count} variant={critical ? 'critical' : 'default'} />
            </span>
          )}
        </Button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={6}
          className="z-50 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-0 shadow-[--shadow-md]"
        >
          <NotificationCenter wsId={ws_id} onNavigate={() => setOpen(false)} />
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  )
}
