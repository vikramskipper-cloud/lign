import { Menu } from 'lucide-react'
import { Button } from '@/ui/button'
import { Breadcrumb } from '@/shell/Breadcrumb'
import { UserMenu } from '@/shell/UserMenu'
import { NotificationBell } from '@/features/notifications/NotificationBell'
import { RealtimeIndicator } from '@/features/realtime/RealtimeIndicator'

interface Props {
  onOpenNav?: () => void
}

export function TopBar({ onOpenNav }: Props) {
  return (
    <header className="sticky top-0 z-30 flex h-14 items-center gap-3 border-b border-[--color-border] bg-[--color-surface] px-4">
      {onOpenNav && (
        <Button
          variant="ghost"
          size="icon"
          aria-label="Open navigation"
          onClick={onOpenNav}
          className="md:hidden"
        >
          <Menu className="h-4 w-4" />
        </Button>
      )}
      <div className="grid h-8 w-8 shrink-0 place-items-center rounded-[--radius-md] bg-[--color-text] text-[--color-brand-fg]">
        <span className="text-sm font-bold">L</span>
      </div>
      <div className="min-w-0 flex-1">
        <Breadcrumb />
      </div>
      <RealtimeIndicator />
      <NotificationBell />
      <UserMenu />
    </header>
  )
}
