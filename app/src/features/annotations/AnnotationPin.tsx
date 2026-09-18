import { cn } from '@/lib/cn'
import type { AnnotationRow, PointPosition } from './queries'

interface Props {
  annotation: AnnotationRow
  number: number | undefined
  focused: boolean
  onClick: () => void
}

/**
 * Round pin marker rendered inside a normalized-coordinate overlay.
 * State color is hard-coded per APP 005 freeze: open=blue, resolved=green.
 * The pin renders only the annotation number.
 */
export function AnnotationPin({ annotation, number, focused, onClick }: Props) {
  const pos = annotation.position as PointPosition
  const resolved = annotation.status !== 'active' || annotation.resolved_at !== null
  return (
    <button
      type="button"
      aria-label={`Pin #${number ?? '?'} — ${resolved ? 'resolved' : 'open'}`}
      onClick={(e) => {
        e.stopPropagation()
        onClick()
      }}
      className={cn(
        'absolute grid h-6 w-6 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full text-[10px] font-semibold text-white shadow-md outline-none transition-transform hover:scale-110',
        focused && 'ring-2 ring-[--color-brand] ring-offset-2 ring-offset-white',
      )}
      style={{
        left: `${pos.x * 100}%`,
        top: `${pos.y * 100}%`,
        backgroundColor: resolved
          ? 'var(--color-state-resolved)'
          : 'var(--color-state-open)',
      }}
    >
      {number ?? '?'}
    </button>
  )
}
