import { CloudOff, RefreshCw } from 'lucide-react'
import * as Tooltip from '@radix-ui/react-tooltip'
import { useRealtimeConnection } from './RealtimeProvider'

/**
 * APP 011 §8.3 — advisory only.
 *
 * Renders NOTHING when live or idle. The app has always worked without a
 * websocket (React Query polls on staleTime, focus and reconnect), so a healthy
 * socket is not news and a broken one is not an error — it is a silent
 * degradation back to the prior behaviour (Freeze Index §7.4).
 */
export function RealtimeIndicator() {
  const status = useRealtimeConnection()
  if (status === 'live' || status === 'idle') return null

  const reconnecting = status === 'connecting'
  const label = reconnecting
    ? 'Reconnecting — updates may be delayed'
    : 'Offline — updates will appear on refresh'

  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>
        <span
          role="status"
          aria-label={label}
          className="grid h-8 w-8 place-items-center text-[--color-text-subtle]"
        >
          {reconnecting ? (
            <RefreshCw className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <CloudOff className="h-3.5 w-3.5" />
          )}
        </span>
      </Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content
          side="bottom"
          sideOffset={6}
          className="z-50 rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1 text-xs text-[--color-text-muted] shadow-[--shadow-sm]"
        >
          {label}
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  )
}
