import * as React from 'react'
import { useNavigate } from 'react-router'
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
  Play,
  Pause,
  Rewind,
  CheckCircle2,
  XCircle,
  RotateCcw,
  MoreVertical,
  Link as LinkIcon,
  Bookmark,
  BookmarkCheck,
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
  useOpenReview,
  useSetReviewState,
  useCompleteReview,
  useReopenReview,
  useToggleBookmark,
  useRespondToReview,
} from './mutations'
import type { ReviewDetail } from './queries'

interface Props {
  detail: ReviewDetail
  caps: Record<string, boolean> | undefined
  isBookmarked: boolean
  isMyPending: boolean
}

export function ReviewActions({ detail, caps, isBookmarked, isMyPending }: Props) {
  const r = detail.review
  const copy = useCopyLink()
  const openR = useOpenReview(r.workspace_id, r.project_id)
  const setState = useSetReviewState(r.workspace_id, r.project_id)
  const complete = useCompleteReview(r.workspace_id, r.project_id, r.root_review_id)
  const reopen = useReopenReview(r.workspace_id, r.project_id, r.root_review_id)
  const bookmark = useToggleBookmark(r.workspace_id)
  const respond = useRespondToReview(r.workspace_id, r.project_id, r.id)

  const [cancelOpen, setCancelOpen] = React.useState(false)
  const [reopenOpen, setReopenOpen] = React.useState(false)
  const navigate = useNavigate()

  const canCoordinate = Boolean(caps?.['review.coordinate'])
  const canComplete = Boolean(caps?.['review.complete'])
  const canReopen = Boolean(caps?.['review.reopen'])
  const canParticipate = Boolean(caps?.['review.participate'])

  const status = r.status

  return (
    <>
      <div className="flex items-center gap-2">
        {isMyPending && canParticipate && (
          <div className="flex items-center gap-1">
            <Button size="sm" variant="secondary" onClick={() => respond.mutate({ response: 'commented' })} disabled={respond.isPending}>
              Comment
            </Button>
            <Button size="sm" onClick={() => respond.mutate({ response: 'signed_off' })} disabled={respond.isPending}>
              Sign off
            </Button>
            <Button size="sm" variant="ghost" onClick={() => respond.mutate({ response: 'declined' })} disabled={respond.isPending}>
              Decline
            </Button>
          </div>
        )}

        {(status === 'draft' || status === 'ready_for_review') && canCoordinate && (
          <Button size="sm" onClick={() => openR.mutate(r.id)} disabled={openR.isPending}>
            <Play className="mr-1 h-3.5 w-3.5" />
            Open review
          </Button>
        )}
        {status === 'in_progress' && canCoordinate && (
          <Button size="sm" variant="secondary" onClick={() => setState.mutate({ reviewId: r.id, target: 'waiting' })} disabled={setState.isPending}>
            <Pause className="mr-1 h-3.5 w-3.5" />
            Pause
          </Button>
        )}
        {status === 'waiting' && canCoordinate && (
          <Button size="sm" variant="secondary" onClick={() => setState.mutate({ reviewId: r.id, target: 'in_progress' })} disabled={setState.isPending}>
            <Rewind className="mr-1 h-3.5 w-3.5" />
            Resume
          </Button>
        )}
        {(status === 'open' || status === 'in_progress' || status === 'waiting') && canComplete && (
          <Button size="sm" onClick={() => complete.mutate({ reviewId: r.id, terminal: 'completed' })} disabled={complete.isPending}>
            <CheckCircle2 className="mr-1 h-3.5 w-3.5" />
            Complete
          </Button>
        )}
        {status === 'completed' && canReopen && (
          <Button size="sm" variant="secondary" onClick={() => setReopenOpen(true)}>
            <RotateCcw className="mr-1 h-3.5 w-3.5" />
            Reopen (new round)
          </Button>
        )}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" aria-label="More actions">
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => copy('review', r.id)}>
              <LinkIcon className="h-4 w-4" />
              Copy link
            </DropdownMenuItem>
            <DropdownMenuItem
              onSelect={() => bookmark.mutate({ subjectKind: 'review', subjectId: r.id })}
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
            {(status !== 'completed' && status !== 'cancelled') && canComplete && (
              <>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  className="text-[--color-danger]"
                  onSelect={() => setCancelOpen(true)}
                >
                  <XCircle className="h-4 w-4" />
                  Cancel review
                </DropdownMenuItem>
              </>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>

      <CancelReviewDialog
        open={cancelOpen}
        onOpenChange={setCancelOpen}
        onConfirm={(reason) =>
          complete.mutate({ reviewId: r.id, terminal: 'cancelled', cancellationReason: reason })
        }
        pending={complete.isPending}
      />
      <ReopenReviewDialog
        open={reopenOpen}
        onOpenChange={setReopenOpen}
        onConfirm={(carry) =>
          reopen.mutate(
            { reviewId: r.id, carryForwardAnnotations: carry },
            {
              onSuccess: (newId) =>
                navigate(`/workspace/${r.workspace_id}/project/${r.project_id}/review/${newId}`),
            },
          )
        }
        pending={reopen.isPending}
      />
    </>
  )
}

function CancelReviewDialog({
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
          <DialogTitle>Cancel review</DialogTitle>
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
            {pending ? 'Cancelling…' : 'Cancel review'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ReopenReviewDialog({
  open,
  onOpenChange,
  onConfirm,
  pending,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
  onConfirm: (carryForward: boolean) => void
  pending: boolean
}) {
  const [carry, setCarry] = React.useState(false)
  React.useEffect(() => {
    if (!open) setCarry(false)
  }, [open])
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Start a new round</DialogTitle>
          <DialogDescription>
            Creates a new draft review linked to this one. The roster is inherited; edit as needed before opening.
          </DialogDescription>
        </DialogHeader>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={carry} onChange={(e) => setCarry(e.target.checked)} disabled={pending} />
          Carry forward active annotations
        </label>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button size="sm" disabled={pending} onClick={() => onConfirm(carry)}>
            {pending ? 'Starting…' : 'Start round'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
