import * as React from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import {
  UserPlus,
  Trash2,
  CheckCircle2,
  XCircle,
  MinusCircle,
  Circle,
  Star,
  StarOff,
  ShieldCheck,
  ShieldOff,
  MoreVertical,
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
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { FormRow } from '@/ui/form-row'
import {
  useAddApprover,
  useRemoveApprover,
  useSetApproverRequired,
  useSetApproverVetoPower,
} from './mutations'
import type { ApprovalSlot, ApprovalStatus } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  workspaceId: string
  projectId: string
  approvalRequestId: string
  approvalStatus: ApprovalStatus
  slots: ApprovalSlot[]
  canManage: boolean
  canAssignVeto: boolean
  focusedSlotId: string | null
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

export function ApprovalRosterEditor({
  workspaceId,
  projectId,
  approvalRequestId,
  approvalStatus,
  slots,
  canManage,
  canAssignVeto,
  focusedSlotId,
  focusRef,
}: Props) {
  const [addOpen, setAddOpen] = React.useState(false)
  const [removing, setRemoving] = React.useState<ApprovalSlot | null>(null)

  const terminal =
    approvalStatus === 'approved' ||
    approvalStatus === 'rejected' ||
    approvalStatus === 'expired' ||
    approvalStatus === 'cancelled' ||
    approvalStatus === 'superseded'
  const canEdit = canManage && !terminal

  const remove = useRemoveApprover(workspaceId, projectId, approvalRequestId)
  const setRequired = useSetApproverRequired(approvalRequestId)
  const setVeto = useSetApproverVetoPower(approvalRequestId)

  return (
    <div
      ref={focusRef}
      className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3"
    >
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">
          Approvers ({slots.filter((s) => !s.removed_at).length})
        </h3>
        {canEdit && (
          <Button size="sm" variant="secondary" onClick={() => setAddOpen(true)}>
            <UserPlus className="mr-1 h-3.5 w-3.5" />
            Add
          </Button>
        )}
      </div>

      <ul className="space-y-1">
        {slots.length === 0 && (
          <li className="rounded-[--radius-sm] border border-dashed border-[--color-border] px-3 py-2 text-xs text-[--color-text-subtle]">
            No approvers assigned.
          </li>
        )}
        {slots.map((s) => (
          <SlotRow
            key={s.id}
            slot={s}
            focused={focusedSlotId === s.id}
            canEdit={canEdit}
            canAssignVeto={canAssignVeto}
            onRequiredToggle={() =>
              setRequired.mutate({ slotId: s.id, required: !s.required })
            }
            onVetoToggle={() =>
              setVeto.mutate({ slotId: s.id, vetoPower: !s.veto_power })
            }
            onRemove={() => setRemoving(s)}
          />
        ))}
      </ul>

      {addOpen && (
        <AddApproverDialog
          workspaceId={workspaceId}
          projectId={projectId}
          approvalRequestId={approvalRequestId}
          existing={slots}
          canAssignVeto={canAssignVeto}
          open={addOpen}
          onOpenChange={setAddOpen}
        />
      )}
      {removing && (
        <RemoveApproverDialog
          slot={removing}
          open={Boolean(removing)}
          onOpenChange={(o) => !o && setRemoving(null)}
          onConfirm={(reason) =>
            remove.mutate(
              { slotId: removing.id, reason },
              { onSuccess: () => setRemoving(null) },
            )
          }
          pending={remove.isPending}
        />
      )}
    </div>
  )
}

function SlotRow({
  slot,
  focused,
  canEdit,
  canAssignVeto,
  onRequiredToggle,
  onVetoToggle,
  onRemove,
}: {
  slot: ApprovalSlot
  focused: boolean
  canEdit: boolean
  canAssignVeto: boolean
  onRequiredToggle: () => void
  onVetoToggle: () => void
  onRemove: () => void
}) {
  const StatusIcon = decisionIcon(slot.response?.decision ?? null)
  return (
    <li
      className={cn(
        'flex items-center gap-2 rounded-[--radius-sm] border border-transparent px-2 py-1.5 text-sm',
        focused && 'border-[--color-border-strong] bg-[--color-surface-2]',
        slot.removed_at && 'opacity-60',
      )}
    >
      <StatusIcon className={cn('h-4 w-4 shrink-0', decisionColor(slot.response?.decision ?? null))} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate font-medium">{slot.display_name ?? '(unknown)'}</span>
          {slot.identity === 'stakeholder' && (
            <span className="rounded bg-[--color-surface-2] px-1 py-0 text-[9px] uppercase text-[--color-text-subtle]">
              Stakeholder
            </span>
          )}
          {!slot.required && (
            <span className="rounded bg-[--color-surface-2] px-1 py-0 text-[9px] uppercase text-[--color-text-subtle]">
              Optional
            </span>
          )}
          {slot.veto_power && (
            <span
              title="Veto power"
              className="inline-flex items-center gap-0.5 rounded bg-[--color-warning]/15 px-1 py-0 text-[9px] font-medium text-[--color-warning]"
            >
              <ShieldCheck className="h-2.5 w-2.5" /> Veto
            </span>
          )}
        </div>
        <div className="text-[10px] text-[--color-text-subtle]">
          {slot.response
            ? `${slot.response.decision}${slot.response.is_veto_cast ? ' (veto)' : ''}`
            : 'Awaiting decision'}
          {slot.removed_at && ' · removed'}
        </div>
      </div>
      {canEdit && !slot.removed_at && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-6 w-6" aria-label="Approver actions">
              <MoreVertical className="h-3.5 w-3.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={onRequiredToggle}>
              {slot.required ? (
                <>
                  <StarOff className="h-4 w-4" /> Mark optional
                </>
              ) : (
                <>
                  <Star className="h-4 w-4" /> Mark required
                </>
              )}
            </DropdownMenuItem>
            {canAssignVeto && (
              <DropdownMenuItem onSelect={onVetoToggle}>
                {slot.veto_power ? (
                  <>
                    <ShieldOff className="h-4 w-4" /> Remove veto
                  </>
                ) : (
                  <>
                    <ShieldCheck className="h-4 w-4" /> Grant veto
                  </>
                )}
              </DropdownMenuItem>
            )}
            <DropdownMenuSeparator />
            <DropdownMenuItem className="text-[--color-danger]" onSelect={onRemove}>
              <Trash2 className="h-4 w-4" /> Remove
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </li>
  )
}

function decisionIcon(d: 'approved' | 'rejected' | 'abstained' | null) {
  switch (d) {
    case 'approved':
      return CheckCircle2
    case 'rejected':
      return XCircle
    case 'abstained':
      return MinusCircle
    default:
      return Circle
  }
}
function decisionColor(d: 'approved' | 'rejected' | 'abstained' | null) {
  switch (d) {
    case 'approved':
      return 'text-[--color-state-resolved]'
    case 'rejected':
      return 'text-[--color-danger]'
    case 'abstained':
      return 'text-[--color-warning]'
    default:
      return 'text-[--color-text-subtle]'
  }
}

function AddApproverDialog({
  workspaceId,
  projectId,
  approvalRequestId,
  existing,
  canAssignVeto,
  open,
  onOpenChange,
}: {
  workspaceId: string
  projectId: string
  approvalRequestId: string
  existing: ApprovalSlot[]
  canAssignVeto: boolean
  open: boolean
  onOpenChange: (o: boolean) => void
}) {
  const raw = useRawProjectParticipants(projectId, open)
  const add = useAddApprover(workspaceId, projectId, approvalRequestId)
  const [selectedId, setSelectedId] = React.useState<string | null>(null)
  const [required, setRequired] = React.useState(true)
  const [vetoPower, setVetoPower] = React.useState(false)
  const [sort, setSort] = React.useState('0')

  React.useEffect(() => {
    if (!open) {
      setSelectedId(null)
      setRequired(true)
      setVetoPower(false)
      setSort('0')
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
    const key = r.workspace_member_id
      ? `wm:${r.workspace_member_id}`
      : r.stakeholder_id
        ? `sh:${r.stakeholder_id}`
        : ''
    return key && !existingIds.has(key)
  })

  const onConfirm = () => {
    if (!selectedId) return
    const r = (raw.data ?? []).find((x) => x.id === selectedId)
    if (!r) return
    add.mutate(
      {
        wmId: r.workspace_member_id ?? null,
        shId: r.stakeholder_id ?? null,
        required,
        vetoPower,
        sortOrder: Number(sort) || 0,
      },
      { onSuccess: () => onOpenChange(false) },
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add approver</DialogTitle>
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
          {canAssignVeto && (
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={vetoPower}
                onChange={(e) => setVetoPower(e.target.checked)}
                disabled={add.isPending}
              />
              Veto power
            </label>
          )}
          <FormRow label="Sort order">
            <Input
              type="number"
              value={sort}
              onChange={(e) => setSort(e.target.value)}
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
            {add.isPending ? 'Adding…' : 'Add approver'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function RemoveApproverDialog({
  slot,
  open,
  onOpenChange,
  onConfirm,
  pending,
}: {
  slot: ApprovalSlot
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
          <DialogTitle>Remove approver</DialogTitle>
          <DialogDescription>
            Removing {slot.display_name ?? 'this approver'}. If they've already decided, they'll be soft-removed to preserve history.
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
