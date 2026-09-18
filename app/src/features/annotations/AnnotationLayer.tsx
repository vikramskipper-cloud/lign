import * as React from 'react'
import { useNavigate, useSearchParams } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import { invalidateAnnotationsForVersion } from '@/features/shared/invalidate'
import { eventToNormalizedPoint, pointsToRegion } from './coords'
import { AnnotationPin } from './AnnotationPin'
import { AnnotationRegion } from './AnnotationRegion'
import { useAnnotationsForVersion } from './queries'
import { useAnnotationNumbering } from './numbering'
import type { AnnotationRow, PointPosition } from './queries'
import { cn } from '@/lib/cn'

export type AuthoringMode = null | 'point' | 'region'

interface Props {
  workspaceId: string
  projectId: string
  versionId: string
  versionFileId: string
  workspaceHref: string
  mode: AuthoringMode
  onModeChange: (m: AuthoringMode) => void
}

/**
 * Absolute overlay sibling to an image viewer. Renders active annotations for
 * the current file and captures pointer events when authoring is active.
 * Coordinates are normalized fractions of the container rect (the container
 * must be the exact rendered rect of the media).
 */
export function AnnotationLayer({
  workspaceId,
  projectId,
  versionId,
  versionFileId,
  workspaceHref,
  mode,
  onModeChange,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const focusedId = searchParams.get('annotation')
  const navigate = useNavigate()
  const qc = useQueryClient()
  const { user } = useSession()
  const containerRef = React.useRef<HTMLDivElement | null>(null)
  const [drawStart, setDrawStart] = React.useState<PointPosition | null>(null)
  const [drawCurr, setDrawCurr] = React.useState<PointPosition | null>(null)

  const annotations = useAnnotationsForVersion(versionId)
  const numbering = useAnnotationNumbering(versionId)

  const create = useMutation({
    mutationFn: async (row: {
      anchor_kind: 'point' | 'region'
      position: object
    }): Promise<string> => {
      if (!user) throw new Error('Not signed in')
      const { data, error } = await supabase
        .from('annotations')
        .insert({
          workspace_id: workspaceId,
          asset_version_id: versionId,
          version_file_id: versionFileId,
          author_profile_id: user.id,
          anchor_kind: row.anchor_kind,
          position: row.position,
          status: 'active',
        })
        .select('id')
        .single()
      if (error) throw error
      return data.id as string
    },
    onSuccess: (id) => {
      invalidateAnnotationsForVersion(qc, versionId)
      onModeChange(null)
      // Navigate to focus the new pin + open its composer via URL param.
      const next = new URLSearchParams(searchParams)
      next.set('tab', 'comments')
      next.set('annotation', id)
      navigate(`${workspaceHref}?${next.toString()}`, { replace: true })
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      projectId // silence unused
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const active = (annotations.data ?? []).filter(
    (a) => a.version_file_id === versionFileId && a.anchor_kind !== 'time',
  )
  // Hide resolved by default UNLESS the deep-link is pointing at one.
  const visible = active.filter(
    (a) =>
      focusedId === a.id || (a.status === 'active' && a.resolved_at === null),
  )

  const cursor = mode === 'point' ? 'cursor-crosshair' : mode === 'region' ? 'cursor-crosshair' : ''
  const captureEvents = mode !== null

  const onPointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    if (mode !== 'region' || !containerRef.current) return
    e.preventDefault()
    const rect = containerRef.current.getBoundingClientRect()
    const p = eventToNormalizedPoint(e.clientX, e.clientY, rect)
    setDrawStart(p)
    setDrawCurr(p)
  }

  const onPointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (mode !== 'region' || !drawStart || !containerRef.current) return
    const rect = containerRef.current.getBoundingClientRect()
    setDrawCurr(eventToNormalizedPoint(e.clientX, e.clientY, rect))
  }

  const onPointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!containerRef.current) return
    if (mode === 'point') {
      const rect = containerRef.current.getBoundingClientRect()
      const p = eventToNormalizedPoint(e.clientX, e.clientY, rect)
      create.mutate({ anchor_kind: 'point', position: p })
    } else if (mode === 'region' && drawStart && drawCurr) {
      const region = pointsToRegion(drawStart, drawCurr)
      setDrawStart(null)
      setDrawCurr(null)
      // Ignore vanishingly small drags (treated as clicks) — user probably
      // meant a point; cancel and let them retry.
      if (region.w < 0.02 && region.h < 0.02) {
        return
      }
      create.mutate({ anchor_kind: 'region', position: region })
    }
  }

  const onFocusExisting = (id: string) => {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.set('tab', 'comments')
        next.set('annotation', id)
        return next
      },
      { replace: true },
    )
  }

  return (
    <div
      ref={containerRef}
      className={cn('absolute inset-0', cursor)}
      style={{ pointerEvents: captureEvents ? 'auto' : 'none' }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
    >
      {/* pointer-events:none on the container by default; children re-enable */}
      {visible.map((a) => (
        <div key={a.id} style={{ pointerEvents: 'auto' }}>
          {a.anchor_kind === 'point' && (
            <AnnotationPin
              annotation={a}
              number={numbering.numberFor(a.id)}
              focused={focusedId === a.id}
              onClick={() => onFocusExisting(a.id)}
            />
          )}
          {a.anchor_kind === 'region' && (
            <AnnotationRegion
              annotation={a}
              number={numbering.numberFor(a.id)}
              focused={focusedId === a.id}
              onClick={() => onFocusExisting(a.id)}
            />
          )}
        </div>
      ))}
      {mode === 'region' && drawStart && drawCurr && (
        <DrawingRegion start={drawStart} curr={drawCurr} />
      )}
    </div>
  )
}

function DrawingRegion({ start, curr }: { start: PointPosition; curr: PointPosition }) {
  const region = pointsToRegion(start, curr)
  return (
    <div
      className="pointer-events-none absolute"
      style={{
        left: `${region.x * 100}%`,
        top: `${region.y * 100}%`,
        width: `${region.w * 100}%`,
        height: `${region.h * 100}%`,
        border: '2px dashed var(--color-state-open)',
        backgroundColor: 'var(--color-state-open-bg)',
      }}
    />
  )
}

/**
 * Fetch a single annotation row (used by AnnotationTimeMarker + hover previews).
 * Re-exports the query hook for feature siblings.
 */
export function useAnnotationsForVersionFile(
  versionId: string | undefined,
  versionFileId: string | null | undefined,
): AnnotationRow[] {
  const q = useAnnotationsForVersion(versionId)
  return React.useMemo(
    () =>
      (q.data ?? []).filter(
        (a) => a.version_file_id === (versionFileId ?? null),
      ),
    [q.data, versionFileId],
  )
}
