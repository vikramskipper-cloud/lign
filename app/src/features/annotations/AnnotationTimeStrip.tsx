import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useSearchParams } from 'react-router'
import { toast } from 'sonner'
import { Plus } from 'lucide-react'
import { Button } from '@/ui/button'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import { invalidateAnnotationsForVersion } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { useAnnotationsForVersion, type AnnotationRow, type TimePosition } from './queries'
import { useAnnotationNumbering } from './numbering'
import { cn } from '@/lib/cn'

interface Props {
  workspaceId: string
  projectId: string
  versionId: string
  versionFileId: string
  workspaceHref: string
  /** Callback returning the current time from the underlying video element. */
  getCurrentTime: () => number
  /** Callback to seek the video (used when a marker is clicked). */
  seekTo: (t: number) => void
  duration: number
  canAnnotate: boolean
}

/**
 * Companion strip below a video that displays time-anchored annotation ticks
 * and an "Add time comment" button that captures the current time.
 */
export function AnnotationTimeStrip({
  workspaceId,
  projectId,
  versionId,
  versionFileId,
  workspaceHref,
  getCurrentTime,
  seekTo,
  duration,
  canAnnotate,
}: Props) {
  const qc = useQueryClient()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const focusedId = searchParams.get('annotation')
  const { user } = useSession()
  const annotations = useAnnotationsForVersion(versionId)
  const numbering = useAnnotationNumbering(versionId)

  const create = useMutation({
    mutationFn: async (t: number): Promise<string> => {
      if (!user) throw new Error('Not signed in')
      const { data, error } = await supabase
        .from('annotations')
        .insert({
          workspace_id: workspaceId,
          asset_version_id: versionId,
          version_file_id: versionFileId,
          author_profile_id: user.id,
          anchor_kind: 'time',
          position: { t } as TimePosition,
          status: 'active',
        })
        .select('id')
        .single()
      if (error) throw error
      return data.id as string
    },
    onSuccess: (id) => {
      invalidateAnnotationsForVersion(qc, versionId)
      const next = new URLSearchParams(searchParams)
      next.set('tab', 'comments')
      next.set('annotation', id)
      navigate(`${workspaceHref}?${next.toString()}`, { replace: true })
      // silence unused
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      projectId
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const timeAnnotations = (annotations.data ?? []).filter(
    (a) => a.anchor_kind === 'time' && a.version_file_id === versionFileId,
  )
  const visible = timeAnnotations.filter(
    (a) => focusedId === a.id || (a.status === 'active' && a.resolved_at === null),
  )

  return (
    <div className="flex items-center gap-2 border-t border-[--color-border] bg-[--color-surface] p-2">
      {canAnnotate && (
        <Button
          size="sm"
          variant="secondary"
          onClick={() => create.mutate(getCurrentTime())}
          disabled={create.isPending}
        >
          <Plus className="mr-1 h-3.5 w-3.5" />
          Add time comment
        </Button>
      )}
      <div className="relative h-4 flex-1 rounded-full bg-[--color-surface-2]">
        {duration > 0 &&
          visible.map((a) => {
            const t = (a.position as TimePosition).t
            const pct = Math.min(1, Math.max(0, t / duration))
            const num = numbering.numberFor(a.id)
            const resolved = a.status !== 'active' || a.resolved_at !== null
            return (
              <button
                key={a.id}
                type="button"
                onClick={() => seekTo(t)}
                title={`Pin #${num ?? '?'} at ${formatTime(t)}`}
                className={cn(
                  'absolute top-0 h-full w-[3px] -translate-x-1/2 outline-none',
                  focusedId === a.id && 'ring-2 ring-[--color-brand] ring-offset-1',
                )}
                style={{
                  left: `${pct * 100}%`,
                  backgroundColor: resolved
                    ? 'var(--color-state-resolved)'
                    : 'var(--color-state-open)',
                }}
                aria-label={`Pin #${num ?? '?'} at ${formatTime(t)}`}
              />
            )
          })}
      </div>
    </div>
  )
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60)
  return `${m}:${s.toString().padStart(2, '0')}`
}

/** Utility export so a parent can decide whether to render the strip. */
export function hasTimeAnnotations(list: AnnotationRow[]): boolean {
  return list.some((a) => a.anchor_kind === 'time')
}
