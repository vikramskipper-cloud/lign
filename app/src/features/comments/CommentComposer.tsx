import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Send, X } from 'lucide-react'
import { Button } from '@/ui/button'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import {
  invalidateCommentsForVersion,
  invalidateAnnotationsForVersion,
} from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { useProjectParticipants, type Participant } from '@/features/participants/queries'
import { MentionPicker } from './MentionPicker'
import { cn } from '@/lib/cn'

interface Target {
  workspaceId: string
  projectId: string
  versionId: string
  /**
   * Which column receives the FK. Exactly one of the two: version or annotation.
   */
  scope:
    | { kind: 'version' }
    | { kind: 'annotation'; annotationId: string }
}

interface Props {
  target: Target
  parentCommentId?: string | null
  autoFocus?: boolean
  compactUntilFocus?: boolean
  placeholder?: string
  onSubmitted?: (commentId: string) => void
  onCancel?: () => void
}

/**
 * Plain-text composer with @-mention typeahead. Inserts a new comment row
 * under RLS (author = auth.uid enforced by policy). Emits nothing further —
 * mention notifications are the Notifications slice's concern.
 */
export function CommentComposer({
  target,
  parentCommentId,
  autoFocus,
  compactUntilFocus,
  placeholder,
  onSubmitted,
  onCancel,
}: Props) {
  const qc = useQueryClient()
  const { user } = useSession()
  const [body, setBody] = React.useState('')
  const [focused, setFocused] = React.useState(!compactUntilFocus)
  const textareaRef = React.useRef<HTMLTextAreaElement | null>(null)

  // Mention typeahead state
  const [mentionQuery, setMentionQuery] = React.useState<string | null>(null)
  const [caretAnchor, setCaretAnchor] = React.useState<DOMRect | null>(null)
  const participants = useProjectParticipants(target.projectId)

  React.useEffect(() => {
    if (autoFocus) textareaRef.current?.focus()
  }, [autoFocus])

  const create = useMutation({
    mutationFn: async (): Promise<string> => {
      if (!user) throw new Error('Not signed in')
      const trimmed = body.trim()
      if (!trimmed) throw new Error('Empty comment')
      const row: Record<string, unknown> = {
        workspace_id: target.workspaceId,
        parent_comment_id: parentCommentId ?? null,
        body: trimmed,
        author_profile_id: user.id,
      }
      if (target.scope.kind === 'version') {
        row.target_version_id = target.versionId
      } else {
        row.target_annotation_id = target.scope.annotationId
      }
      const { data, error } = await supabase
        .from('comments')
        .insert(row)
        .select('id')
        .single()
      if (error) throw error
      return data.id as string
    },
    onSuccess: (id) => {
      setBody('')
      invalidateCommentsForVersion(qc, target.versionId)
      // If this comment is targeting an annotation, the pin's "has thread"
      // affordance may change — bump annotations too.
      if (target.scope.kind === 'annotation') {
        invalidateAnnotationsForVersion(qc, target.versionId)
      }
      onSubmitted?.(id)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const onBodyChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value
    setBody(value)
    updateMentionState(value, e.target)
  }

  const updateMentionState = (value: string, el: HTMLTextAreaElement) => {
    const caret = el.selectionStart ?? value.length
    const upTo = value.slice(0, caret)
    const at = upTo.lastIndexOf('@')
    if (at < 0) return setMentionQuery(null)
    const between = upTo.slice(at + 1)
    if (/\s/.test(between)) return setMentionQuery(null)
    // Also stop if the char before @ is not whitespace or line start
    if (at > 0 && !/\s/.test(upTo[at - 1]!)) return setMentionQuery(null)
    setMentionQuery(between)
    // Anchor near the textarea; caret positioning without a measurement lib
    // is imprecise, but "top of the textarea" reads fine for a small pop.
    const rect = el.getBoundingClientRect()
    setCaretAnchor(new DOMRect(rect.left, rect.top, rect.width, 0))
  }

  const applyMention = (p: Participant) => {
    const el = textareaRef.current
    if (!el) return
    const caret = el.selectionStart ?? body.length
    const upTo = body.slice(0, caret)
    const at = upTo.lastIndexOf('@')
    if (at < 0) return
    const insert = `@${p.displayName} `
    const next = body.slice(0, at) + insert + body.slice(caret)
    setBody(next)
    setMentionQuery(null)
    // Restore caret after the inserted mention (async to survive React re-render).
    requestAnimationFrame(() => {
      const pos = at + insert.length
      el.setSelectionRange(pos, pos)
      el.focus()
    })
  }

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Cmd/Ctrl+Enter submits.
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault()
      if (body.trim()) create.mutate()
    }
  }

  if (compactUntilFocus && !focused && !body) {
    return (
      <button
        type="button"
        onClick={() => setFocused(true)}
        className="w-full rounded-[--radius-md] border border-dashed border-[--color-border] bg-[--color-surface] px-3 py-2 text-left text-sm text-[--color-text-subtle] hover:bg-[--color-surface-2]"
      >
        {placeholder ?? 'Start a discussion…'}
      </button>
    )
  }

  return (
    <div className="space-y-1.5">
      <textarea
        ref={textareaRef}
        value={body}
        onChange={onBodyChange}
        onKeyDown={onKeyDown}
        onFocus={() => setFocused(true)}
        placeholder={placeholder ?? 'Write a comment…'}
        rows={3}
        disabled={create.isPending}
        className={cn(
          'w-full resize-y rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 py-2 text-sm outline-none',
          'placeholder:text-[--color-text-subtle] focus:border-[--color-border-strong]',
          'disabled:cursor-not-allowed disabled:opacity-50',
        )}
      />
      <div className="flex items-center justify-between">
        <p className="text-[10px] text-[--color-text-subtle]">
          Type <kbd className="rounded bg-[--color-surface-2] px-1">@</kbd> to mention · <kbd className="rounded bg-[--color-surface-2] px-1">⌘↵</kbd> to send
        </p>
        <div className="flex items-center gap-1">
          {onCancel && (
            <Button variant="ghost" size="sm" onClick={onCancel} disabled={create.isPending}>
              <X className="mr-1 h-3.5 w-3.5" />
              Cancel
            </Button>
          )}
          <Button
            size="sm"
            onClick={() => create.mutate()}
            disabled={create.isPending || !body.trim()}
          >
            {create.isPending ? (
              'Sending…'
            ) : (
              <>
                <Send className="mr-1 h-3.5 w-3.5" />
                {parentCommentId ? 'Reply' : 'Comment'}
              </>
            )}
          </Button>
        </div>
      </div>
      {mentionQuery !== null && participants.data && (
        <MentionPicker
          participants={participants.data}
          query={mentionQuery}
          onSelect={applyMention}
          onDismiss={() => setMentionQuery(null)}
          anchorRect={caretAnchor}
        />
      )}
    </div>
  )
}
