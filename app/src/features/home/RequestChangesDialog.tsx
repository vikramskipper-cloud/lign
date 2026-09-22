import * as React from 'react'
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/ui/dialog'
import type { ApprovalItem } from './queries'

/**
 * "Request changes" requires a comment — an approval record with no stated
 * reason is close to useless when it is read back later, and the RPC will
 * accept a null comment, so the guard has to live here.
 */
export function RequestChangesDialog({
  item, onClose, onSubmit,
}: {
  item: ApprovalItem | null
  onClose: () => void
  onSubmit: (comment: string) => void
}) {
  const [comment, setComment] = React.useState('')
  const [touched, setTouched] = React.useState(false)
  React.useEffect(() => { if (item) { setComment(''); setTouched(false) } }, [item])

  const empty = comment.trim().length === 0

  return (
    <Dialog open={Boolean(item)} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="lign-warm sm:max-w-md" style={{ background: 'var(--surface)' }}>
        <form
          onSubmit={(e) => {
            e.preventDefault()
            setTouched(true)
            if (empty) return
            onSubmit(comment)
          }}
        >
          <DialogHeader>
            <DialogTitle>Request changes</DialogTitle>
            <DialogDescription>
              {item ? `${item.code} · ${item.title}` : ''} — say what needs to change. This is
              recorded on the approval and cannot be edited afterwards.
            </DialogDescription>
          </DialogHeader>

          <div style={{ marginTop: 14 }}>
            <label htmlFor="rc-comment" style={{ display: 'block', fontSize: 13.5, fontWeight: 500, color: 'var(--ink)', marginBottom: 6 }}>
              What needs to change?
            </label>
            <textarea
              id="rc-comment"
              className="auth-field"
              required
              rows={4}
              autoFocus
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              onBlur={() => setTouched(true)}
              aria-invalid={touched && empty ? true : undefined}
              aria-describedby={touched && empty ? 'rc-error' : undefined}
              style={{ height: 'auto', padding: '10px 12px', resize: 'vertical', lineHeight: 1.5 }}
            />
            {touched && empty && (
              <p id="rc-error" role="alert" style={{ margin: '6px 0 0', fontSize: 12.5, color: 'var(--error-text)' }}>
                A comment is required to request changes.
              </p>
            )}
          </div>

          <DialogFooter style={{ marginTop: 16 }}>
            <button type="button" onClick={onClose} style={{ height: 36, padding: '0 14px', borderRadius: 7, background: 'var(--surface)', border: '1px solid var(--border)', cursor: 'pointer', fontSize: 13 }}>
              Cancel
            </button>
            <button type="submit" disabled={empty} style={{ height: 36, padding: '0 14px', borderRadius: 7, background: 'var(--accent)', color: '#fff', border: 'none', cursor: empty ? 'not-allowed' : 'pointer', opacity: empty ? 0.6 : 1, fontSize: 13 }}>
              Request changes
            </button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
