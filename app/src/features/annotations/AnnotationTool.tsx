import { MapPin, Square, X } from 'lucide-react'
import { Button } from '@/ui/button'
import { cn } from '@/lib/cn'
import type { AuthoringMode } from './AnnotationLayer'

interface Props {
  mode: AuthoringMode
  onChange: (m: AuthoringMode) => void
  canAnnotate: boolean
}

/**
 * Floating pill anchored to the top-right of the viewer container. When a
 * mode is active, the AnnotationLayer captures pointer events. Esc cancels
 * (wired via useWorkspaceHotkeys).
 */
export function AnnotationTool({ mode, onChange, canAnnotate }: Props) {
  if (!canAnnotate) return null
  return (
    <div className="absolute right-3 top-3 z-10 flex items-center gap-1 rounded-full border border-[--color-border] bg-[--color-surface] p-1 shadow-[--shadow-sm]">
      <Button
        size="sm"
        variant={mode === 'point' ? 'primary' : 'ghost'}
        onClick={() => onChange(mode === 'point' ? null : 'point')}
        title="Add pin (P)"
        className={cn('h-7 px-2 text-xs')}
      >
        <MapPin className="mr-1 h-3.5 w-3.5" />
        Pin
      </Button>
      <Button
        size="sm"
        variant={mode === 'region' ? 'primary' : 'ghost'}
        onClick={() => onChange(mode === 'region' ? null : 'region')}
        title="Draw area"
        className={cn('h-7 px-2 text-xs')}
      >
        <Square className="mr-1 h-3.5 w-3.5" />
        Area
      </Button>
      {mode !== null && (
        <Button
          size="sm"
          variant="ghost"
          onClick={() => onChange(null)}
          title="Cancel (Esc)"
          className="h-7 px-2 text-xs"
        >
          <X className="h-3.5 w-3.5" />
        </Button>
      )}
    </div>
  )
}
