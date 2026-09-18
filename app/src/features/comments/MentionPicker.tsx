import * as React from 'react'
import { cn } from '@/lib/cn'
import type { Participant } from '@/features/participants/queries'

interface Props {
  participants: Participant[]
  query: string
  onSelect: (p: Participant) => void
  onDismiss: () => void
  /** Anchor rect (in client coordinates) for absolute positioning. */
  anchorRect: DOMRect | null
}

/**
 * Typeahead popup for @-mentions. Rendered when the composer detects an
 * unbroken @-token being typed. Positioned above the caret via anchorRect.
 * Enter/Tab select; Esc dismisses; Up/Down navigate. Filters by
 * displayName prefix (case-insensitive) with a stable order.
 */
export function MentionPicker({
  participants,
  query,
  onSelect,
  onDismiss,
  anchorRect,
}: Props) {
  const filtered = React.useMemo(() => {
    const q = query.trim().toLowerCase()
    const matched = q
      ? participants.filter((p) => p.displayName.toLowerCase().includes(q))
      : participants
    return matched.slice(0, 8)
  }, [participants, query])

  const [index, setIndex] = React.useState(0)
  React.useEffect(() => setIndex(0), [query])

  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        setIndex((i) => Math.min(i + 1, filtered.length - 1))
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        setIndex((i) => Math.max(i - 1, 0))
      } else if (e.key === 'Enter' || e.key === 'Tab') {
        if (filtered[index]) {
          e.preventDefault()
          onSelect(filtered[index]!)
        }
      } else if (e.key === 'Escape') {
        e.preventDefault()
        onDismiss()
      }
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [filtered, index, onSelect, onDismiss])

  if (!anchorRect || filtered.length === 0) return null

  const top = anchorRect.top - 8
  const left = anchorRect.left

  return (
    <div
      role="listbox"
      className="fixed z-50 max-h-56 w-64 -translate-y-full overflow-y-auto rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-1 shadow-[--shadow-md]"
      style={{ top, left }}
    >
      {filtered.map((p, i) => (
        <button
          key={p.id}
          type="button"
          role="option"
          aria-selected={i === index}
          onMouseEnter={() => setIndex(i)}
          onClick={() => onSelect(p)}
          className={cn(
            'flex w-full items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-left text-sm',
            i === index ? 'bg-[--color-surface-2]' : 'hover:bg-[--color-surface-2]',
          )}
        >
          <div className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-[--color-surface-2] text-[10px] font-medium text-[--color-text-muted]">
            {p.displayName.slice(0, 1).toUpperCase()}
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate">{p.displayName}</div>
            <div className="truncate text-[10px] text-[--color-text-subtle]">
              {p.kind === 'stakeholder' ? 'Stakeholder · ' : ''}
              {p.role}
            </div>
          </div>
        </button>
      ))}
    </div>
  )
}
