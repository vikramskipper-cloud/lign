import { Badge } from '@/ui/badge'
import { cn } from '@/lib/cn'

/**
 * Small neutral pill for a discipline label. Text-only per D14.
 * Truncates when the surrounding container constrains width.
 */
export function DisciplineChip({
  name,
  className,
}: {
  name: string
  className?: string
}) {
  return (
    <Badge
      variant="neutral"
      className={cn('max-w-[10rem] truncate', className)}
      title={name}
    >
      {name}
    </Badge>
  )
}
