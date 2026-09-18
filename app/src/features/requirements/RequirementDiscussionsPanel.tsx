import * as React from 'react'
import { EmptyState } from '@/ui/empty-state'
import { Button } from '@/ui/button'
import { relative, absolute } from '@/lib/formatDate'
import { useRequirementDiscussions } from './queries'
import { useCreateRequirementComment } from './mutations'

interface Props {
  workspaceId: string
  requirementId: string
  canComment: boolean
}

/**
 * Requirement-scoped discussions. Uses the additive comments.target_requirement_id
 * arm added by APP 008 §3.7. This is a minimal thread-per-comment renderer;
 * full APP 005 CommentsPanel reuse would require a version anchor which this
 * scope does not have.
 */
export function RequirementDiscussionsPanel({
  workspaceId,
  requirementId,
  canComment,
}: Props) {
  const q = useRequirementDiscussions(requirementId)
  const create = useCreateRequirementComment()
  const [body, setBody] = React.useState('')

  const submit = async () => {
    if (!body.trim()) return
    await create.mutateAsync({
      workspaceId,
      requirementId,
      body: body.trim(),
    })
    setBody('')
  }

  const rows = q.data ?? []

  return (
    <div className="space-y-3 p-3">
      {canComment && (
        <div className="space-y-2">
          <textarea
            className="min-h-16 w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm outline-none focus-visible:ring-1 focus-visible:ring-[--color-border-strong]"
            placeholder="Discuss this requirement…"
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
          <div className="flex justify-end">
            <Button
              size="sm"
              disabled={!body.trim() || create.isPending}
              onClick={submit}
            >
              Post
            </Button>
          </div>
        </div>
      )}
      {q.isLoading ? (
        <p className="text-xs text-[--color-text-muted]">Loading…</p>
      ) : rows.length === 0 ? (
        <EmptyState title="No discussions yet" />
      ) : (
        <ul className="space-y-2">
          {rows.map((c) => (
            <li
              key={c.id}
              className="rounded-[--radius-sm] border border-[--color-border] p-2 text-sm"
            >
              <div className="flex items-center gap-2 text-xs">
                <span className="font-medium">
                  {c.author?.display_name ?? 'Unknown'}
                </span>
                <span
                  className="text-[10px] text-[--color-text-subtle]"
                  title={absolute(c.created_at)}
                >
                  {relative(c.created_at)}
                </span>
              </div>
              <p className="mt-1 whitespace-pre-wrap text-[--color-text]">
                {c.body}
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
