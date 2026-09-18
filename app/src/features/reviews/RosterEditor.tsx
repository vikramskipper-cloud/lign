import * as React from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import {
  UserPlus,
  Trash2,
  RefreshCw,
  CheckCircle2,
  XCircle,
  MessageSquare,
  Circle,
  Star,
  StarOff,
} from 'lucide-react'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { FormRow } from '@/ui/form-row'
import {
  useAddReviewer,
  useRemoveReviewer,
  useReassignReviewer,
  useSetReviewerRequired,
} from './mutations'
import type { ReviewParticipant, ReviewStatus } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  workspaceId: string
  projectId: string
  reviewId: string
  reviewStatus: ReviewStatus
  participants: ReviewParticipant[]
  canCoordinate: boolean
  focusedParticipantId: string | null
  focusRef?: React.MutableRefObject<HTMLDivElement | null>
}

interface RawParticipantRow {
  id: string
  workspace_member_id: string | null
  stakeholder_id: string | null
  role: string
  workspace_member: {
    user_id: string
    profile: { id: string; display_name: string } | null
  } | null
  stakeholder: {
    display_name: string | null
    email: string
  } | null
}

function useRawProjectParticipants(projectId: string, enabled: boolean) {
  return useQuery({
    queryKey: ['project', projectId, 'participants', 'raw'],
    enabled: enabled && Boolean(projectId),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('project_participants')
        .select(
          'id, workspace_member_id, stakeholder_id, role, ' +
            'workspace_member:workspace_members!project_participants_workspace_member_id_fkey(' +
            'user_id, profile:profiles!workspace_members_user_id_fkey(id, display_name)), ' +
            'stakeholder:stakeholders!project_participants_stakeholder_id_fkey(display_name, email)',
        )
        .eq('project_id', projectId)
        .eq('status', 'active')
      if (error) throw error
      return (data ?? []) as unknown as RawParticipantRow[]
    },
  })
}

export function RosterEditor({
  workspaceId,
  projectId,
  reviewId,
  reviewStatus,
  participants,
  canCoordinate,
  focusedParticipantId,
  focusRef,
}: Props) {
  const [addOpen, setAddOpen] = React.useState(false)
  const [reassigning, setReassigning] = React.useState<ReviewParticipant | null>(null)
  const [removing, setRemoving] = React.useState<ReviewParticipant | null>(null)

  const terminal = reviewStatus === 'completed' || reviewStatus === 'cancelled'
  const canEdit = canCoordinate && !terminal

  const remove = useRemoveReviewer(workspaceId, projectId, reviewId)
  const setRequired = useSetReviewerRequired(reviewId)

  return (
    <div ref={focusRef} className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Reviewers ({participants.filter((p) => !p.removed_at).length})</h3>
        {canEdit && (
          <Button size="sm" variant="secondary" onClick={() => setAddOpen(true)}>
            <UserPlus className="mr-1 h-3.5 w-3.5" />
            Add
          </Button>
        )}
      </div>

      <ul className="space-y-1">
        {participants.length === 0 && (
          <li className="rounded-[--radius-sm] border border-dashed border-[--color-border] px-3 py-2 text-xs text-[--color-text-subtle]">
            No reviewers assigned.
          </li>
        )}
        {participants.map((p) => (
          <ParticipantRow
            key={p.id}
            p={p}
            focused={focusedParticipantId === p.id}
            canEdit={canEdit}
            onRequiredToggle={() => setRequired.mutate({ participantId: p.id, required: !p.required })}
            onReassign={() => setReassigning(p)}
            onRemove={() => setRemoving(p)}
          />
        ))}
      </ul>

      {addOpen && (
        <AddReviewerDialog
          workspaceId={workspaceId}
          projectId={projectId}
          reviewId={reviewId}
          existing={participants}
          open={addOpen}
          onOpenChange={setAddOpen}
        />
      )}
      {reassigning && (
        <ReassignReviewerDialog
          projectId={projectId}
          participant={reassigning}
          existing={participants}
          reviewId={reviewId}
          workspaceId={workspaceId}
          open={Boolean(reassigning)}
          onOpenChange={(o) => !o && setReassigning(null)}
        />
      )}
      {removing && (
        <RemoveReviewerDialog
          participant={removing}
          open={Boolean(removing)}
          onOpenChange={(o) => !o && setRemoving(null)}
          onConfirm={(reason) =>
            remove.mutate(
              { participantId: removing.id, reason },
              {
                onSuccess: () => setRemoving(null),
              },
            )
          }
          pending={remove.isPending}
        />
      )}
    </div>
  )
}

function ParticipantRow({
  p,
  focused,
  canEdit,
  onRequiredToggle,
  onReassign,
  onRemove,
}: {
  p: ReviewParticipant
  focused: boolean
  canEdit: boolean
  onRequiredToggle: () => void
  onReassign: () => void
  onRemove: () => void
}) {
  const StatusIcon = statusIcon(p.status)
  return (
    <li
      className={cn(
        'flex items-center gap-2 rounded-[--radius-sm] border border-transparent px-2 py-1.5 text-sm',
        focused && 'border-[--color-border-strong] bg-[--color-surface-2]',
        p.removed_at && 'opacity-60',
      )}
    >
      <StatusIcon className={cn('h-4 w-4 shrink-0', statusColor(p.status))} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate font-medium">{p.display_name ?? '(unknown)'}</span>
          {p.identity === 'stakeholder' && (
            <span className="rounded bg-[--color-surface-2] px-1 py-0 text-[9px] uppercase text-[--color-text-subtle]">Stakeholder</span>
          )}
          {!p.required && (
            <span className="rounded bg-[--color-surface-2] px-1 py-0 text-[9px] uppercase text-[--color-text-subtle]">Optional</span>
          )}
        </div>
        <div className="text-[10px] text-[--color-text-subtle]">
          {p.status === 'pending' ? 'Awaiting response' : p.status.replace('_', ' ')}
          {p.removed_at && ' · removed'}
        </div>
      </div>
      {canEdit && !p.removed_at && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-6 w-6" aria-label="Reviewer actions">
              <MessageSquare className="h-3.5 w-3.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={onRequiredToggle}>
              {p.required ? (
                <>
                  <StarOff className="h-4 w-4" /> Mark optional
                </>
              ) : (
                <>
                  <Star className="h-4 w-4" /> Mark required
                </>
              )}
            </DropdownMenuItem>
            {p.status === 'pending' && (
              <DropdownMenuItem onSelect={onReassign}>
                <RefreshCw className="h-4 w-4" /> Reassign
              </DropdownMenuItem>
            )}
            <DropdownMenuItem className="text-[--color-danger]" onSelect={onRemove}>
              <Trash2 className="h-4 w-4" /> Remove
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </li>
  )
}

function statusIcon(s: ReviewParticipant['status']) {
  switch (s) {
    case 'signed_off':
      return CheckCircle2
    case 'declined':
      return XCircle
    case 'commented':
      return MessageSquare
    default:
      return Circle
  }
}
function statusColor(s: ReviewParticipant['status']) {
  switch (s) {
    case 'signed_off':
      return 'text-[--color-state-resolved]'
    case 'declined':
      return 'text-[--color-danger]'
    case 'commented':
      return 'text-[--color-state-open]'
    default:
      return 'text-[--color-text-subtle]'
  }
}

function AddReviewerDialog({
  workspaceId,
  projectId,
  reviewId,
  existing,
  open,
  onOpenChange,
}: {
  workspaceId: string
  projectId: string
  reviewId: string
  existing: ReviewParticipant[]
  open: boolean
  onOpenChange: (o: boolean) => void
}) {
  const raw = useRawProjectParticipants(projectId, open)
  const add = useAddReviewer(workspaceId, projectId)
  const [selectedId, setSelectedId] = React.useState<string | null>(null)
  const [required, setRequired] = React.useState(true)
  const [seq, setSeq] = React.useState('0')

  React.useEffect(() => {
    if (!open) {
      setSelectedId(null)
      setRequired(true)
      setSeq('0')
    }
  }, [open])

  const existingIds = React.useMemo(() => {
    const s = new Set<string>()
    existing.forEach((p) => {
      if (p.removed_at) return
      if (p.workspace_member_id) s.add(`wm:${p.workspace_member_id}`)
      if (p.stakeholder_id) s.add(`sh:${p.stakeholder_id}`)
    })
    return s
  }, [existing])

  const available = (raw.data ?? []).filter((r) => {
    const key = r.workspace_member_id ? `wm:${r.workspace_member_id}` : r.stakeholder_id ? `sh:${r.stakeholder_id}` : ''
    return key && !existingIds.has(key)
  })

  const onConfirm = () => {
    if (!selectedId) return
    const r = (raw.data ?? []).find((x) => x.id === selectedId)
    if (!r) return
    add.mutate(
      {
        reviewId,
        wmId: r.workspace_member_id ?? null,
        shId: r.stakeholder_id ?? null,
        required,
        sequenceIndex: Number(seq) || 0,
      },
      { onSuccess: () => onOpenChange(false) },
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add reviewer</DialogTitle>
          <DialogDescription>
            Only active project participants may be added.
          </DialogDescription>
        </DialogHeader>
        <FormRow label="Participant" required>
          <select
            value={selectedId ?? ''}
            onChange={(e) => setSelectedId(e.target.value || null)}
            disabled={add.isPending}
            className="h-9 w-full rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 text-sm"
          >
            <option value="">Select a participant…</option>
            {available.map((r) => (
              <option key={r.id} value={r.id}>
                {r.workspace_member?.profile?.display_name ??
                  r.stakeholder?.display_name ??
                  r.stakeholder?.email ??
                  'Unknown'}
                {r.stakeholder_id ? ' (stakeholder)' : ''} · {r.role}
              </option>
            ))}
          </select>
        </FormRow>
        <div className="grid grid-cols-2 gap-3">
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={required}
              onChange={(e) => setRequired(e.target.checked)}
              disabled={add.isPending}
            />
            Required
          </label>
          <FormRow label="Sequence index" hint="For sequential policy.">
            <Input
              type="number"
              value={seq}
              onChange={(e) => setSeq(e.target.value)}
              min={0}
              disabled={add.isPending}
            />
          </FormRow>
        </div>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)} disabled={add.isPending}>
            Cancel
          </Button>
          <Button size="sm" onClick={onConfirm} disabled={add.isPending || !selectedId}>
            {add.isPending ? 'Adding…' : 'Add reviewer'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ReassignReviewerDialog({
  projectId,
  participant,
  existing,
  reviewId,
  workspaceId,
  open,
  onOpenChange,
}: {
  projectId: string
  participant: ReviewParticipant
  existing: ReviewParticipant[]
  reviewId: string
  workspaceId: string
  open: boolean
  onOpenChange: (o: boolean) => void
}) {
  const raw = useRawProjectParticipants(projectId, open)
  const reassign = useReassignReviewer(workspaceId, projectId, reviewId)
  const [selectedId, setSelectedId] = React.useState<string | null>(null)

  const existingIds = React.useMemo(() => {
    const s = new Set<string>()
    existing.forEach((p) => {
      if (p.removed_at || p.id === participant.id) return
      if (p.workspace_member_id) s.add(`wm:${p.workspace_member_id}`)
      if (p.stakeholder_id) s.add(`sh:${p.stakeholder_id}`)
    })
    return s
  }, [existing, participant.id])

  const available = (raw.data ?? []).filter((r) => {
    const key = r.workspace_member_id ? `wm:${r.workspace_member_id}` : r.stakeholder_id ? `sh:${r.stakeholder_id}` : ''
    return key && !existingIds.has(key)
  })

  const onConfirm = () => {
    if (!selectedId) return
    const r = (raw.data ?? []).find((x) => x.id === selectedId)
    if (!r) return
    reassign.mutate(
      {
        participantId: participant.id,
        newWmId: r.workspace_member_id ?? null,
        newShId: r.stakeholder_id ?? null,
      },
      { onSuccess: () => onOpenChange(false) },
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Reassign reviewer</DialogTitle>
          <DialogDescription>
            Replacing {participant.display_name}. Sequence and required flag are preserved.
          </DialogDescription>
        </DialogHeader>
        <FormRow label="New reviewer" required>
          <select
            value={selectedId ?? ''}
            onChange={(e) => setSelectedId(e.target.value || null)}
            disabled={reassign.isPending}
            className="h-9 w-full rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 text-sm"
          >
            <option value="">Select a participant…</option>
            {available.map((r) => (
              <option key={r.id} value={r.id}>
                {r.workspace_member?.profile?.display_name ??
                  r.stakeholder?.display_name ??
                  r.stakeholder?.email ??
                  'Unknown'}
                {r.stakeholder_id ? ' (stakeholder)' : ''}
              </option>
            ))}
          </select>
        </FormRow>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)} disabled={reassign.isPending}>
            Cancel
          </Button>
          <Button size="sm" onClick={onConfirm} disabled={reassign.isPending || !selectedId}>
            {reassign.isPending ? 'Reassigning…' : 'Reassign'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function RemoveReviewerDialog({
  participant,
  open,
  onOpenChange,
  onConfirm,
  pending,
}: {
  participant: ReviewParticipant
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
          <DialogTitle>Remove reviewer</DialogTitle>
          <DialogDescription>
            Removing {participant.display_name}. If they've already responded, they'll be soft-removed to preserve history.
          </DialogDescription>
        </DialogHeader>
        <FormRow label="Reason" required>
          <Input value={reason} onChange={(e) => setReason(e.target.value)} autoFocus minLength={3} disabled={pending} />
        </FormRow>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button
            size="sm"
            variant="destructive"
            disabled={pending || reason.trim().length < 3}
            onClick={() => onConfirm(reason.trim())}
          >
            {pending ? 'Removing…' : 'Remove'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
