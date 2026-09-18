import { cn } from '@/lib/cn'
import type { AnnotationRow, RegionPosition } from './queries'

interface Props {
  annotation: AnnotationRow
  number: number | undefined
  focused: boolean
  onClick: () => void
}

export function AnnotationRegion({ annotation, number, focused, onClick }: Props) {
  const pos = annotation.position as RegionPosition
  const resolved = annotation.status !== 'active' || annotation.resolved_at !== null
  const color = resolved ? 'var(--color-state-resolved)' : 'var(--color-state-open)'
  const bg = resolved ? 'var(--color-state-resolved-bg)' : 'var(--color-state-open-bg)'
  return (
    <button
      type="button"
      aria-label={`Region #${number ?? '?'} — ${resolved ? 'resolved' : 'open'}`}
      onClick={(e) => {
        e.stopPropagation()
        onClick()
      }}
      className={cn(
        'absolute cursor-pointer outline-none',
        focused && 'ring-2 ring-[--color-brand] ring-offset-2 ring-offset-white',
      )}
      style={{
        left: `${pos.x * 100}%`,
        top: `${pos.y * 100}%`,
        width: `${pos.w * 100}%`,
        height: `${pos.h * 100}%`,
        border: `2px solid ${color}`,
        backgroundColor: bg,
      }}
    >
      <span
        className="absolute -left-px -top-4 rounded-t-md px-1.5 py-0.5 text-[10px] font-semibold text-white"
        style={{ backgroundColor: color }}
      >
        {number ?? '?'}
      </span>
    </button>
  )
}
