import * as React from 'react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { FormRow } from '@/ui/form-row'
import {
  Send,
  CheckCircle2,
  XCircle,
  MinusCircle,
  ShieldCheck,
  MoreVertical,
  Link as LinkIcon,
  Bookmark,
  BookmarkCheck,
  Clock,
} from 'lucide-react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { useCopyLink } from '@/features/comments/useCopyLink'
import {
  useSendApprovalRequest,
  useCancelApproval,
  useExpireApproval,
  useRespondToApproval,
  useToggleApprovalBookmark,
} from './mutations'
import type { ApprovalDetail, ApprovalSlot } from './queries'

interface Props {
  detail: ApprovalDetail
  caps: Record<string, boolean> | undefined
  isBookmarked: boolean
  mySlot: ApprovalSlot | null
}

export function ApprovalActions({ detail, caps, isBookmarked, mySlot }: Props) {
  const r = detail.request
  const copy = useCopyLink()
  const send = useSendApprovalRequest(r.workspace_id, r.project_id, r.version_id)
  const cancel = useCancelApproval(r.workspace_id, r.project_id, r.id, r.root_approval_request_id ?? undefined, r.version_id)
  const expire = useExpireApproval(r.workspace_id, r.project_id, r.id, r.root_approval_request_id ?? undefined, r.version_id)
  const respond = useRespondToApproval(
    r.workspace_id,
    r.project_id,
    r.id,
    r.root_approval_request_id ?? undefined,
    r.version_id,
  )
  const bookmark = useToggleApprovalBookmark(r.workspace_id)

  const [cancelOpen, setCancelOpen] = React.useState(false)
  const [respondOpen, setRespondOpen] = React.useState<null | 'approved' | 'rejected' | 'abstained'>(
    null,
  )

  const canRequest = Boolean(caps?.['approval.request'])
  const canCancel = Boolean(caps?.['approval.cancel'])
  const canExpire = Boolean(caps?.['approval.expire'])
  const canRespond = Boolean(caps?.['approval.respond'])

  const status = r.status
  const isTerminal =
    status === 'approved' ||
    status === 'rejected' ||
    status === 'expired' ||
    status === 'cancelled' ||
    status === 'superseded'
  const isPendingMe =
    !!mySlot &&
    !mySlot.removed_at &&
    !mySlot.response &&
    (status === 'pending' || status === 'in_progress')

  return (
    <>
      <div className="flex items-center gap-2">
        {isPendingMe && canRespond && (
          <div className="flex items-center gap-1">
            <Button size="sm" onClick={() => setRespondOpen('approved')} disabled={respond.isPending}>
              <CheckCircle2 className="mr-1 h-3.5 w-3.5" />
              Approve
            </Button>
            <Button size="sm" variant="secondary" onClick={() => setRespondOpen('rejected')} disabled={respond.isPending}>
              <XCircle className="mr-1 h-3.5 w-3.5" />
              Reject
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setRespondOpen('abstained')} disabled={respond.isPending}>
              <MinusCircle className="mr-1 h-3.5 w-3.5" />
              Abstain
            </Button>
          </div>
        )}

        {status === 'draft' && canRequest && (
          <Button size="sm" onClick={() => send.mutate(r.id)} disabled={send.isPending}>
            <Send className="mr-1 h-3.5 w-3.5" />
            Send
          </Button>
        )}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" aria-label="More actions">
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => copy('approval', r.id)}>
              <LinkIcon className="h-4 w-4" />
              Copy link
            </DropdownMenuItem>
            <DropdownMenuItem
              onSelect={() => bookmark.mutate({ subjectId: r.id })}
            >
              {isBookmarked ? (
                <>
                  <BookmarkCheck className="h-4 w-4" />
                  Remove bookmark
                </>
              ) : (
                <>
                  <Bookmark className="h-4 w-4" />
                  Bookmark
                </>
              )}
            </DropdownMenuItem>
            {!isTerminal && canCancel && (
              <>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  className="text-[--color-danger]"
                  onSelect={() => setCancelOpen(true)}
                >
                  <XCircle className="h-4 w-4" />
                  Cancel approval
                </DropdownMenuItem>
              </>
            )}
            {(status === 'pending' || status === 'in_progress') && canExpire && (
              <DropdownMenuItem onSelect={() => expire.mutate({ reason: 'Force-expired' })}>
                <Clock className="h-4 w-4" />
                Force expire
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <RespondDialog
        open={respondOpen !== null}
        decision={respondOpen}
        canVeto={Boolean(mySlot?.veto_power)}
        onOpenChange={(o) => !o && setRespondOpen(null)}
        onConfirm={(comment, isVetoCast) => {
          if (!mySlot || !respondOpen) return
          respond.mutate(
            {
              slotId: mySlot.id,
              decision: respondOpen,
              comment,
              isVetoCast,
            },
            { onSuccess: () => setRespondOpen(null) },
          )
        }}
        pending={respond.isPending}
      />

      <CancelApprovalDialog
        open={cancelOpen}
        onOpenChange={setCancelOpen}
        onConfirm={(reason) => cancel.mutate({ reason }, { onSuccess: () => setCancelOpen(false) })}
        pending={cancel.isPending}
      />
    </>
  )
}

function RespondDialog({
  open,
  decision,
  canVeto,
  onOpenChange,
  onConfirm,
  pending,
}: {
  open: boolean
  decision: 'approved' | 'rejected' | 'abstained' | null
  canVeto: boolean
  onOpenChange: (o: boolean) => void
  onConfirm: (comment: string, isVetoCast: boolean) => void
  pending: boolean
}) {
  const [comment, setComment] = React.useState('')
  const [castVeto, setCastVeto] = React.useState(false)
  React.useEffect(() => {
    if (!open) {
      setComment('')
      setCastVeto(false)
    }
  }, [open])

  const label =
    decision === 'approved' ? 'Approve' : decision === 'rejected' ? 'Reject' : 'Abstain'
  const needsConfirm = decision === 'rejected' || decision === 'abstained'

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{label} approval</DialogTitle>
          <DialogDescription>
            {needsConfirm
              ? 'This decision is immutable — you cannot change it later. Please record a reason for the audit trail.'
              : 'Your decision is immutable once cast. Please record a note for the audit trail.'}
          </DialogDescription>
        </DialogHeader>
        <FormRow label="Reason / note" required hint="3–2000 characters">
          <Input
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            autoFocus
            minLength={3}
            maxLength={2000}
            disabled={pending}
          />
        </FormRow>
        {decision === 'rejected' && canVeto && (
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={castVeto}
              onChange={(e) => setCastVeto(e.target.checked)}
              disabled={pending}
            />
            <ShieldCheck className="h-3.5 w-3.5 text-[--color-warning]" />
            Cast as veto (terminates the request immediately)
          </label>
        )}
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button
            size="sm"
            variant={decision === 'rejected' ? 'destructive' : 'primary'}
            disabled={pending || comment.trim().length < 3}
            onClick={() => onConfirm(comment.trim(), castVeto)}
          >
            {pending ? 'Submitting…' : label}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function CancelApprovalDialog({
  open,
  onOpenChange,
  onConfirm,
  pending,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
  onConfirm: (reason: string) => void
  pending: boolean
}) {
  const [reason, setReason] = React.useState('')
  React.useEffect(() => {
    if (!open) setReason('')
  }, [open])
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancel approval</DialogTitle>
          <DialogDescription>
            Cancellation is permanent. Please record a reason for the audit trail.
          </DialogDescription>
        </DialogHeader>
        <FormRow label="Reason" required>
          <Input value={reason} onChange={(e) => setReason(e.target.value)} autoFocus minLength={3} disabled={pending} />
        </FormRow>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)} disabled={pending}>
            Back
          </Button>
          <Button
            size="sm"
            variant="destructive"
            disabled={pending || reason.trim().length < 3}
            onClick={() => onConfirm(reason.trim())}
          >
            {pending ? 'Cancelling…' : 'Cancel approval'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
