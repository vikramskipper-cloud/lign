import * as React from 'react'
import { useSearchParams } from 'react-router'
import { MessageSquare, MapPin } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { Skeleton } from '@/ui/skeleton'
import { Button } from '@/ui/button'
import { useSession } from '@/auth/SessionProvider'
import { useCommentsForVersion, type CommentRow } from './queries'
import {
  useAnnotationsForVersion,
  type AnnotationRow,
} from '@/features/annotations/queries'
import { useAnnotationNumbering } from '@/features/annotations/numbering'
import { useProjectParticipants } from '@/features/participants/queries'
import { CommentComposer } from './CommentComposer'
import { CommentThreadCard } from './CommentThreadCard'
import { CommentFilterBar, type CommentFilter } from './CommentFilterBar'

interface Props {
  workspaceId: string
  projectId: string
  versionId: string
  canComment: boolean
  canResolve: boolean
  canEditOwn: boolean
  /** Callback to focus a pin in the viewer when the user clicks the pin header. */
  onFocusAnnotation?: (annotationId: string) => void
}

/**
 * Right-panel Comments tab body. Renders composer, filter bar, then two
 * sections: Pins (annotation-scoped threads) and General (version-scoped
 * threads). Grouping is a client-side reduce over one merged fetch.
 */
export function CommentsPanel({
  workspaceId,
  projectId,
  versionId,
  canComment,
  canResolve,
  canEditOwn,
  onFocusAnnotation,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const filter = (searchParams.get('comments') as CommentFilter | null) ?? 'all'
  const focusedCommentId = searchParams.get('comment')
  const focusedAnnotationId = searchParams.get('annotation')

  const annotations = useAnnotationsForVersion(versionId)
  const annotationIds = React.useMemo(
    () => (annotations.data ?? []).map((a) => a.id),
    [annotations.data],
  )
  const comments = useCommentsForVersion(versionId, annotationIds)
  const participants = useProjectParticipants(projectId)
  const numbering = useAnnotationNumbering(versionId)
  const { user } = useSession()

  const setFilter = (v: CommentFilter) => {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (v === 'all') next.delete('comments')
        else next.set('comments', v)
        return next
      },
      { replace: true },
    )
  }

  if (comments.isLoading || annotations.isLoading) {
    return (
      <div className="space-y-2 p-3">
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    )
  }

  if (comments.isError) {
    return (
      <div className="p-3">
        <EmptyState
          title="Couldn't load comments"
          action={
            <Button size="sm" variant="secondary" onClick={() => comments.refetch()}>
              Retry
            </Button>
          }
        />
      </div>
    )
  }

  const all = comments.data ?? []
  const annotationMap = new Map<string, AnnotationRow>((annotations.data ?? []).map((a) => [a.id, a]))
  const grouped = groupThreads(all, filter, user?.id ?? null, participants.data ?? [])

  return (
    <div className="flex flex-col gap-3 p-3">
      <div className="flex items-center justify-between">
        <CommentFilterBar value={filter} onChange={setFilter} />
      </div>

      {canComment && (
        <CommentComposer
          target={{ workspaceId, projectId, versionId, scope: { kind: 'version' } }}
          compactUntilFocus
          placeholder="Start a discussion on this version…"
        />
      )}

      {grouped.pins.length === 0 && grouped.general.length === 0 ? (
        <EmptyState
          title={filter === 'all' ? 'No comments yet' : `No comments match "${filterLabel(filter)}"`}
          description={
            filter === 'all' ? 'Start a discussion above.' : undefined
          }
          action={
            filter !== 'all' ? (
              <Button size="sm" variant="secondary" onClick={() => setFilter('all')}>
                Clear filter
              </Button>
            ) : undefined
          }
        />
      ) : (
        <>
          {grouped.pins.length > 0 && (
            <section className="space-y-2">
              <SectionHeader icon={<MapPin className="h-3.5 w-3.5" />}>Pins</SectionHeader>
              {grouped.pins.map(({ root, replies }) => {
                const ann = root.target_annotation_id
                  ? annotationMap.get(root.target_annotation_id)
                  : undefined
                const num = ann ? numbering.numberFor(ann.id) : undefined
                return (
                  <CommentThreadCard
                    key={root.id}
                    root={root}
                    replies={replies}
                    participants={participants.data ?? []}
                    workspaceId={workspaceId}
                    projectId={projectId}
                    versionId={versionId}
                    headerLabel={`Pin #${num ?? '?'}`}
                    headerAction={
                      ann && onFocusAnnotation ? (
                        <button
                          type="button"
                          onClick={() => onFocusAnnotation(ann.id)}
                          className="text-[--color-state-open] hover:underline"
                          aria-label={`Focus pin #${num ?? '?'} in viewer`}
                        >
                          <MapPin className="h-3.5 w-3.5" />
                        </button>
                      ) : undefined
                    }
                    canComment={canComment}
                    canResolve={canResolve}
                    canEditOwn={canEditOwn}
                    focused={
                      root.id === focusedCommentId ||
                      (Boolean(root.target_annotation_id) &&
                        root.target_annotation_id === focusedAnnotationId)
                    }
                  />
                )
              })}
            </section>
          )}
          {grouped.general.length > 0 && (
            <section className="space-y-2">
              <SectionHeader icon={<MessageSquare className="h-3.5 w-3.5" />}>General</SectionHeader>
              {grouped.general.map(({ root, replies }) => (
                <CommentThreadCard
                  key={root.id}
                  root={root}
                  replies={replies}
                  participants={participants.data ?? []}
                  workspaceId={workspaceId}
                  projectId={projectId}
                  versionId={versionId}
                  canComment={canComment}
                  canResolve={canResolve}
                  canEditOwn={canEditOwn}
                  focused={root.id === focusedCommentId}
                />
              ))}
            </section>
          )}

          {/*
           * Bare pins (annotation created but no comment yet) surface a
           * placeholder thread card so the pin is still visible + jumpable
           * from the panel.
           */}
          <BarePinsSection
            annotations={(annotations.data ?? []).filter(
              (a) => a.status === 'active' && !all.some((c) => c.target_annotation_id === a.id),
            )}
            numbering={numbering}
            focusedAnnotationId={focusedAnnotationId}
            workspaceId={workspaceId}
            projectId={projectId}
            versionId={versionId}
            canComment={canComment}
            onFocusAnnotation={onFocusAnnotation}
          />
        </>
      )}
    </div>
  )
}

function SectionHeader({ icon, children }: { icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-1.5 text-[10px] font-medium uppercase tracking-wide text-[--color-text-subtle]">
      {icon}
      {children}
    </div>
  )
}

function BarePinsSection({
  annotations,
  numbering,
  focusedAnnotationId,
  workspaceId,
  projectId,
  versionId,
  canComment,
  onFocusAnnotation,
}: {
  annotations: AnnotationRow[]
  numbering: ReturnType<typeof useAnnotationNumbering>
  focusedAnnotationId: string | null
  workspaceId: string
  projectId: string
  versionId: string
  canComment: boolean
  onFocusAnnotation?: (id: string) => void
}) {
  if (annotations.length === 0) return null
  return (
    <section className="space-y-2">
      <SectionHeader icon={<MapPin className="h-3.5 w-3.5" />}>Pins without a comment</SectionHeader>
      {annotations.map((a) => {
        const focused = a.id === focusedAnnotationId
        return (
          <div
            key={a.id}
            className={
              'space-y-2 rounded-[--radius-md] border p-3 ' +
              (focused
                ? 'border-[--color-border-strong] bg-[--color-surface-2]'
                : 'border-[--color-border] bg-[--color-surface]')
            }
          >
            <div className="flex items-center gap-2">
              {onFocusAnnotation && (
                <button
                  type="button"
                  onClick={() => onFocusAnnotation(a.id)}
                  className="text-[--color-state-open] hover:underline"
                  aria-label={`Focus pin #${numbering.numberFor(a.id) ?? '?'} in viewer`}
                >
                  <MapPin className="h-3.5 w-3.5" />
                </button>
              )}
              <span className="text-xs font-semibold">Pin #{numbering.numberFor(a.id) ?? '?'}</span>
            </div>
            {canComment && (
              <CommentComposer
                target={{
                  workspaceId,
                  projectId,
                  versionId,
                  scope: { kind: 'annotation', annotationId: a.id },
                }}
                compactUntilFocus={!focused}
                placeholder="Start the thread on this pin…"
                autoFocus={focused}
              />
            )}
          </div>
        )
      })}
    </section>
  )
}

interface Thread {
  root: CommentRow
  replies: CommentRow[]
}

function groupThreads(
  all: CommentRow[],
  filter: CommentFilter,
  currentUserId: string | null,
  participants: import('@/features/participants/queries').Participant[],
): { pins: Thread[]; general: Thread[] } {
  const roots = all.filter((c) => c.parent_comment_id === null)
  const byParent = new Map<string, CommentRow[]>()
  for (const c of all) {
    if (c.parent_comment_id) {
      const list = byParent.get(c.parent_comment_id) ?? []
      list.push(c)
      byParent.set(c.parent_comment_id, list)
    }
  }

  const passes = (root: CommentRow, replies: CommentRow[]): boolean => {
    if (filter === 'all') return true
    if (filter === 'unresolved') return root.resolved_at === null
    if (filter === 'mine')
      return [root, ...replies].some((c) => c.author_profile_id === currentUserId)
    if (filter === 'mentions') {
      if (!currentUserId) return false
      const me = participants.find((p) => p.profileId === currentUserId)
      if (!me) return false
      // Plain-text mention match: "@{DisplayName}" appearing in any comment body
      const needle = `@${me.displayName}`
      return [root, ...replies].some((c) => c.body.includes(needle))
    }
    return true
  }

  const pins: Thread[] = []
  const general: Thread[] = []
  for (const root of roots) {
    const replies = (byParent.get(root.id) ?? []).sort((a, b) =>
      a.created_at.localeCompare(b.created_at),
    )
    if (!passes(root, replies)) continue
    if (root.target_annotation_id) pins.push({ root, replies })
    else if (root.target_version_id) general.push({ root, replies })
  }
  return { pins, general }
}

function filterLabel(f: CommentFilter): string {
  return f === 'unresolved' ? 'Unresolved' : f === 'mine' ? 'Mine' : '@ Mentions me'
}
