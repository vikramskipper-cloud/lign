import { cn } from '@/lib/cn'
import type { RequirementPriority } from './queries'

const LABELS: Record<RequirementPriority | 'unset', string> = {
  critical: 'Critical',
  high: 'High',
  medium: 'Medium',
  low: 'Low',
  informational: 'Info',
  unset: 'Unset',
}

const STYLES: Record<RequirementPriority | 'unset', string> = {
  critical:
    'text-[--color-danger] bg-[--color-danger]/10 border border-[--color-danger]/30',
  high:
    'text-[--color-warning] bg-[--color-warning]/15 border border-[--color-warning]/30',
  medium:
    'text-[--color-state-open] bg-[--color-state-open-bg] border border-[--color-state-open]/30',
  low:
    'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]',
  informational:
    'text-[--color-text-subtle] bg-[--color-surface-2] border border-[--color-border]',
  unset:
    'text-[--color-text-subtle] bg-[--color-surface-2] border border-dashed border-[--color-border]',
}

interface Props {
  priority: RequirementPriority | null | undefined
  className?: string
}

/** APP 008 §11.8 primitive: priority indicator. */
export function PriorityBadge({ priority, className }: Props) {
  const key = (priority ?? 'unset') as RequirementPriority | 'unset'
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium',
        STYLES[key],
        className,
      )}
      aria-label={`${LABELS[key]} priority`}
    >
      {LABELS[key]}
    </span>
  )
}
