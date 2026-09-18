import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import { Button } from '@/ui/button'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { invalidateCommentsForVersion } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import type { CommentRow } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  comment: CommentRow
  versionId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

/**
 * Edit-own body dialog. Calls the frozen edit_own_comment RPC which snapshots
 * the previous body into comment_edits and emits comment.edited.
 */
export function EditCommentDialog({ comment, versionId, open, onOpenChange }: Props) {
  const qc = useQueryClient()
  const [body, setBody] = React.useState(comment.body)

  React.useEffect(() => {
    if (open) setBody(comment.body)
  }, [open, comment.body])

  const edit = useMutation({
    mutationFn: async () => {
      const trimmed = body.trim()
      if (!trimmed) throw new Error('Empty comment')
      if (trimmed === comment.body) return
      const { error } = await supabase.rpc('edit_own_comment', {
        p_comment_id: comment.id,
        p_new_body: trimmed,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Comment updated')
      qc.invalidateQueries({ queryKey: qk.comment(comment.id) })
      qc.invalidateQueries({ queryKey: qk.commentEdits(comment.id) })
      invalidateCommentsForVersion(qc, versionId)
      onOpenChange(false)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit comment</DialogTitle>
          <DialogDescription>
            Previous versions are kept in the edit history.
          </DialogDescription>
        </DialogHeader>
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          rows={4}
          autoFocus
          disabled={edit.isPending}
          className={cn(
            'w-full resize-y rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 py-2 text-sm outline-none',
            'focus:border-[--color-border-strong] disabled:opacity-50',
          )}
        />
        <DialogFooter>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => onOpenChange(false)}
            disabled={edit.isPending}
          >
            Cancel
          </Button>
          <Button
            size="sm"
            onClick={() => edit.mutate()}
            disabled={edit.isPending || !body.trim() || body.trim() === comment.body}
          >
            {edit.isPending ? 'Saving…' : 'Save changes'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
