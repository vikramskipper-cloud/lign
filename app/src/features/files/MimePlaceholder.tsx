import { cn } from '@/lib/cn'
import { iconFor, labelFor } from './mime'

interface Props {
  mime: string | null | undefined
  filename?: string
  className?: string
  size?: 'sm' | 'md' | 'lg'
}

/**
 * Placeholder tile for a file that can't be rendered inline (or where the
 * caller wants a compact preview). Renders a lucide mime-icon + short label
 * ("PDF", "IFC", "DWG") on a subtle dashed background.
 */
export function MimePlaceholder({ mime, filename, className, size = 'md' }: Props) {
  const Icon = iconFor(mime)
  const label = labelFor(mime, filename)
  const dims = size === 'sm' ? 'h-4 w-4' : size === 'lg' ? 'h-10 w-10' : 'h-6 w-6'
  return (
    <div
      className={cn(
        'flex h-full w-full flex-col items-center justify-center gap-1.5 rounded-[--radius-md] border border-dashed border-[--color-border] bg-[--color-surface-2] text-[--color-text-subtle]',
        className,
      )}
      role="img"
      aria-label={`${label} file placeholder`}
    >
      <Icon className={dims} />
      <span className="text-[10px] font-medium tracking-wide">{label}</span>
    </div>
  )
}
