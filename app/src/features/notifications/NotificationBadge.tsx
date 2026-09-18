import { cn } from '@/lib/cn'

interface Props {
  count: number
  variant?: 'default' | 'critical'
  className?: string
}

/**
 * APP 010: numeric badge primitive. Reusable on bell + NavRail.
 * Shows 1–99; 100+ shows "99+". Renders nothing when count is 0.
 */
export function NotificationBadge({ count, variant = 'default', className }: Props) {
  if (count <= 0) return null
  const label = count > 99 ? '99+' : String(count)
  return (
    <span
      aria-label={`${count} unread notifications`}
      className={cn(
        'inline-flex min-w-[1.25rem] items-center justify-center rounded-full px-1 text-[0.6875rem] font-semibold leading-4',
        variant === 'critical'
          ? 'bg-[--color-state-blocked] text-white'
          : 'bg-[--color-state-attention] text-white',
        className,
      )}
    >
      {label}
    </span>
  )
}
