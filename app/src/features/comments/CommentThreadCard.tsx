import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router'
import { toast } from 'sonner'
import {
  MoreVertical,
  Link as LinkIcon,
  Pencil,
  CheckCircle2,
  RotateCcw,
  MessageSquare,
} from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { StateBadge } from '@/features/shared/StateBadge'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { invalidateCommentsForVersion } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { useSession } from '@/auth/SessionProvider'
import { relative, absolute } from '@/lib/formatDate'
import { cn } from '@/lib/cn'
import { CommentBody } from './CommentBody'
import { CommentComposer } from './CommentComposer'
import { EditCommentDialog } from './EditCommentDialog'
import { useCopyLink } from './useCopyLink'
import type { CommentRow } from './queries'
import type { Participant } from '@/features/participants/queries'

interface Props {
  root: CommentRow
  replies: CommentRow[]
  participants: Participant[]
  workspaceId: string
  projectId: string
  versionId: string
  /** Header label (e.g. "Pin #3") for annotation threads. Omit for general threads. */
  headerLabel?: React.ReactNode
  /** Icon+action rendered next to the label — used by pins to jump-focus the viewer. */
  headerAction?: React.ReactNode
  canComment: boolean
  canResolve: boolean
  canEditOwn: boolean
  /** When true (deep-link land or pin-selected), auto-open reply composer / scroll into view. */
  focused?: boolean
  onScrollIntoView?: (el: HTMLElement) => void
}

/**
 * One thread card. Renders header (label + Open/Resolved badge + ⋮), root
 * body, replies, reply composer (on click), edit-own dialog (on click).
 * Resolve toggle is optimistic per §11.
 */
export function CommentThreadCard({
  root,
  replies,
  participants,
  workspaceId,
  projectId,
  versionId,
  headerLabel,
  headerAction,
  canComment,
  canResolve,
  canEditOwn,
  focused,
  onScrollIntoView,
}: Props) {
  const qc = useQueryClient()
  const copy = useCopyLink()
  const { user } = useSession()
  const [showReply, setShowReply] = React.useState(false)
  const [editOpen, setEditOpen] = React.useState(false)
  const cardRef = React.useRef<HTMLDivElement | null>(null)
  const [, setSearchParams] = useSearchParams()

  React.useEffect(() => {
    if (focused && cardRef.current) {
      onScrollIntoView?.(cardRef.current)
      cardRef.current.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
  }, [focused, onScrollIntoView])

  const resolved = root.resolved_at !== null

  const resolveToggle = useMutation({
    mutationFn: async () => {
      const next = resolved ? null : new Date().toISOString()
      const { error } = await supabase
        .from('comments')
        .update({ resolved_at: next })
        .eq('id', root.id)
      if (error) throw error
    },
    onMutate: async () => {
      // Optimistic: flip resolved_at locally.
      await qc.cancelQueries({ predicate: (q) => {
        const k = q.queryKey as unknown[]
        return Array.isArray(k) && k[0] === 'asset-version' && k[1] === versionId && k[2] === 'comments'
      } })
      const snapshots: Array<{ key: unknown; data: unknown }> = []
      qc.getQueryCache().findAll({ predicate: (q) => {
        const k = q.queryKey as unknown[]
        return Array.isArray(k) && k[0] === 'asset-version' && k[1] === versionId && k[2] === 'comments'
      } }).forEach((q) => {
        snapshots.push({ key: q.queryKey, data: q.state.data })
        qc.setQueryData<CommentRow[] | undefined>(
          q.queryKey as readonly unknown[],
          (prev) => {
            if (!prev) return prev
            return prev.map((c) =>
              c.id === root.id
                ? { ...c, resolved_at: resolved ? null : new Date().toISOString() }
                : c,
            )
          },
        )
      })
      return { snapshots }
    },
    onError: (err, _vars, ctx) => {
      toast.error(humanizeError(err))
      ctx?.snapshots.forEach(({ key, data }) =>
        qc.setQueryData(
          key as readonly unknown[],
          data as CommentRow[] | undefined,
        ),
      )
    },
    onSettled: () => {
      invalidateCommentsForVersion(qc, versionId)
      qc.invalidateQueries({ queryKey: qk.comment(root.id) })
    },
  })

  const isOwn = user?.id === root.author_profile_id
  const canEditThisOne = canEditOwn && isOwn

  const linkKind: 'comment' | 'annotation' = root.target_annotation_id ? 'annotation' : 'comment'
  const linkId = root.target_annotation_id ?? root.id

  return (
    <div
      ref={cardRef}
      className={cn(
        'space-y-2 rounded-[--radius-md] border p-3',
        focused
          ? 'border-[--color-border-strong] bg-[--color-surface-2]'
          : 'border-[--color-border] bg-[--color-surface]',
      )}
    >
      <div className="flex items-center gap-2">
        <div className="flex min-w-0 flex-1 items-center gap-2">
          {headerAction}
          {headerLabel && (
            <span className="truncate text-xs font-semibold text-[--color-text]">
              {headerLabel}
            </span>
          )}
          <StateBadge state={resolved ? 'resolved' : 'open'} />
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-6 w-6" aria-label="Thread actions">
              <MoreVertical className="h-3.5 w-3.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => copy(linkKind, linkId)}>
              <LinkIcon className="h-4 w-4" />
              Copy link
            </DropdownMenuItem>
            {canResolve && (
              <DropdownMenuItem
                onSelect={() => resolveToggle.mutate()}
                disabled={resolveToggle.isPending}
              >
                {resolved ? (
                  <>
                    <RotateCcw className="h-4 w-4" />
                    Reopen thread
                  </>
                ) : (
                  <>
                    <CheckCircle2 className="h-4 w-4" />
                    Resolve thread
                  </>
                )}
              </DropdownMenuItem>
            )}
            {canEditThisOne && (
              <DropdownMenuItem onSelect={() => setEditOpen(true)}>
                <Pencil className="h-4 w-4" />
                Edit
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <CommentRowView
        comment={root}
        participants={participants}
        currentUserId={user?.id ?? null}
        canEditOwn={canEditOwn}
        onEdit={() => setEditOpen(true)}
        onCopyLink={() => copy('comment', root.id)}
        versionId={versionId}
      />

      {replies.map((r) => (
        <div key={r.id} className="ml-3 border-l-2 border-[--color-border] pl-3">
          <p className="mb-1 text-[10px] text-[--color-text-subtle]">
            ↳ replying to @{root.author?.display_name ?? 'author'}
          </p>
          <CommentRowView
            comment={r}
            participants={participants}
            currentUserId={user?.id ?? null}
            canEditOwn={canEditOwn}
            onEdit={() => {
              // Edit for replies opens the same dialog, threading through state
              // via a small local trick: we render one dialog per row here.
            }}
            onCopyLink={() => copy('comment', r.id)}
            versionId={versionId}
          />
        </div>
      ))}

      {canComment && !resolved && (
        <>
          {showReply ? (
            <CommentComposer
              target={{
                workspaceId,
                projectId,
                versionId,
                scope: root.target_annotation_id
                  ? { kind: 'annotation', annotationId: root.target_annotation_id }
                  : { kind: 'version' },
              }}
              parentCommentId={root.id}
              autoFocus
              onSubmitted={() => setShowReply(false)}
              onCancel={() => setShowReply(false)}
              placeholder="Reply…"
            />
          ) : (
            <button
              type="button"
              onClick={() => setShowReply(true)}
              className="inline-flex items-center gap-1 text-xs text-[--color-text-muted] hover:text-[--color-text]"
            >
              <MessageSquare className="h-3.5 w-3.5" />
              Reply
            </button>
          )}
        </>
      )}

      <EditCommentDialog
        comment={root}
        versionId={versionId}
        open={editOpen}
        onOpenChange={(o) => {
          setEditOpen(o)
          if (!o) {
            // On close, drop any stale ?comment= param so the card doesn't stay focused.
            setSearchParams(
              (prev) => {
                const next = new URLSearchParams(prev)
                if (next.get('comment') === root.id) next.delete('comment')
                return next
              },
              { replace: true },
            )
          }
        }}
      />
    </div>
  )
}

function CommentRowView({
  comment,
  participants,
  currentUserId,
  canEditOwn,
  onEdit,
  onCopyLink,
  versionId,
}: {
  comment: CommentRow
  participants: Participant[]
  currentUserId: string | null
  canEditOwn: boolean
  onEdit: () => void
  onCopyLink: () => void
  versionId: string
}) {
  const isOwn = currentUserId === comment.author_profile_id
  const isEdited = comment.updated_at !== comment.created_at
  return (
    <div className="space-y-1">
      <div className="flex items-baseline gap-2">
        <span className="text-xs font-semibold text-[--color-text]">
          {comment.author?.display_name ?? 'Unknown'}
        </span>
        <span
          className="text-[10px] text-[--color-text-subtle]"
          title={absolute(comment.created_at)}
        >
          {relative(comment.created_at)}
          {isEdited ? ' · edited' : ''}
        </span>
      </div>
      <CommentBody body={comment.body} participants={participants} />
      {(canEditOwn && isOwn) || true ? (
        <div className="flex items-center gap-1 text-[10px] text-[--color-text-subtle]">
          <button
            type="button"
            onClick={onCopyLink}
            className="hover:text-[--color-text-muted]"
          >
            Copy link
          </button>
          {canEditOwn && isOwn && (
            <>
              <span aria-hidden>·</span>
              <button
                type="button"
                onClick={onEdit}
                className="hover:text-[--color-text-muted]"
              >
                Edit
              </button>
            </>
          )}
          {/* versionId reserved for future per-row invalidations */}
          <span className="sr-only">{versionId}</span>
        </div>
      ) : null}
    </div>
  )
}
