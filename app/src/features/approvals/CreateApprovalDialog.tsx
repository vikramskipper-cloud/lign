import * as React from 'react'
import { useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
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
import { useCreateApprovalDraft, useSendApprovalRequest } from './mutations'
import type { ApprovalPolicy } from './queries'
import { useProjectCapabilities } from '@/lib/capabilities'

interface Props {
  workspaceId: string
  projectId: string
  designAssetId: string
  versionId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

interface RawParticipantRow {
  id: string
  workspace_member_id: string | null
  stakeholder_id: string | null
  role: string
  workspace_member: {
    user_id: string
    profile: { id: string; display_name: string; email: string } | null
  } | null
  stakeholder: {
    user_id: string | null
    display_name: string | null
    email: string
    profile: { id: string; display_name: string; email: string } | null
  } | null
}

function useRawParticipants(projectId: string) {
  return useQuery({
    queryKey: ['project', projectId, 'participants', 'raw'],
    enabled: Boolean(projectId),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('project_participants')
        .select(
          'id, workspace_member_id, stakeholder_id, role, ' +
            'workspace_member:workspace_members!project_participants_workspace_member_id_fkey(' +
            'user_id, profile:profiles!workspace_members_user_id_fkey(id, display_name, email)), ' +
            'stakeholder:stakeholders!project_participants_stakeholder_id_fkey(' +
            'user_id, display_name, email, profile:profiles!stakeholders_user_id_fkey(id, display_name, email))',
        )
        .eq('project_id', projectId)
        .eq('status', 'active')
      if (error) throw error
      return (data ?? []) as unknown as RawParticipantRow[]
    },
  })
}

function displayName(r: RawParticipantRow): string {
  return (
    r.workspace_member?.profile?.display_name ??
    r.stakeholder?.profile?.display_name ??
    r.stakeholder?.display_name ??
    r.stakeholder?.email ??
    'Unknown'
  )
}

export function CreateApprovalDialog({
  workspaceId,
  projectId,
  designAssetId,
  versionId,
  open,
  onOpenChange,
}: Props) {
  const navigate = useNavigate()
  const [title, setTitle] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [selectedWm, setSelectedWm] = React.useState<Set<string>>(new Set())
  const [selectedSh, setSelectedSh] = React.useState<Set<string>>(new Set())
  const [policy, setPolicy] = React.useState<ApprovalPolicy>('unanimous')
  const [quorumMin, setQuorumMin] = React.useState('')
  const [dueAt, setDueAt] = React.useState('')
  const [expiresAt, setExpiresAt] = React.useState('')
  const [sendImmediately, setSendImmediately] = React.useState(true)
  const [vetoMap, setVetoMap] = React.useState<Set<string>>(new Set())
  const [optionalMap, setOptionalMap] = React.useState<Set<string>>(new Set())
  const [error, setError] = React.useState<string | undefined>()

  const raw = useRawParticipants(projectId)
  const caps = useProjectCapabilities(projectId, workspaceId)
  const create = useCreateApprovalDraft()
  const send = useSendApprovalRequest(workspaceId, projectId, versionId)

  const canAssignVeto = Boolean(caps.data?.['approval.veto'])

  React.useEffect(() => {
    if (!open) {
      setTitle('')
      setDescription('')
      setSelectedWm(new Set())
      setSelectedSh(new Set())
      setPolicy('unanimous')
      setQuorumMin('')
      setDueAt('')
      setExpiresAt('')
      setSendImmediately(true)
      setVetoMap(new Set())
      setOptionalMap(new Set())
      setError(undefined)
    }
  }, [open])

  const rosterSize = selectedWm.size + selectedSh.size

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (rosterSize < 1) {
      setError('At least one approver is required.')
      return
    }
    if (policy === 'quorum' && (!quorumMin || Number(quorumMin) <= 0)) {
      setError('Quorum requires a positive minimum.')
      return
    }
    setError(undefined)

    // Concatenation order: workspace members first, then stakeholders (F-3.1).
    const wmIds = Array.from(selectedWm)
    const shIds = Array.from(selectedSh)
    const all: Array<{ key: string; isWm: boolean }> = [
      ...wmIds.map((id) => ({ key: `wm:${id}`, isWm: true })),
      ...shIds.map((id) => ({ key: `sh:${id}`, isWm: false })),
    ]
    const required = all.map(({ key }) => !optionalMap.has(key))
    const vetoPower = all.map(({ key }) => vetoMap.has(key))
    const sortOrder = all.map((_, i) => i)

    try {
      const id = await create.mutateAsync({
        workspaceId,
        projectId,
        designAssetId,
        versionId,
        policy,
        approverWmIds: wmIds,
        approverShIds: shIds,
        approverRequired: required,
        approverVetoPower: vetoPower,
        approverSortOrder: sortOrder,
        title: title.trim() || null,
        description: description.trim() || null,
        dueAt: dueAt ? new Date(dueAt).toISOString() : null,
        expiresAt: expiresAt ? new Date(expiresAt).toISOString() : null,
        quorumMin: policy === 'quorum' ? Number(quorumMin) : null,
      })
      if (sendImmediately) {
        await send.mutateAsync(id)
      }
      onOpenChange(false)
      navigate(`/workspace/${workspaceId}/project/${projectId}/approval/${id}`)
    } catch {
      /* toast handled by mutation */
    }
  }

  const toggleRow = (r: RawParticipantRow) => {
    if (r.workspace_member_id) {
      const next = new Set(selectedWm)
      if (next.has(r.workspace_member_id)) next.delete(r.workspace_member_id)
      else next.add(r.workspace_member_id)
      setSelectedWm(next)
    } else if (r.stakeholder_id) {
      const next = new Set(selectedSh)
      if (next.has(r.stakeholder_id)) next.delete(r.stakeholder_id)
      else next.add(r.stakeholder_id)
      setSelectedSh(next)
    }
  }

  const rowKey = (r: RawParticipantRow) =>
    r.workspace_member_id ? `wm:${r.workspace_member_id}` : `sh:${r.stakeholder_id ?? ''}`

  const isSelected = (r: RawParticipantRow) =>
    r.workspace_member_id
      ? selectedWm.has(r.workspace_member_id)
      : r.stakeholder_id
        ? selectedSh.has(r.stakeholder_id)
        : false

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>New approval request</DialogTitle>
          <DialogDescription>
            Approvals target a published version. Choose approvers, policy, and deadline.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="a-title" label="Title">
            <Input
              id="a-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              autoFocus
              disabled={create.isPending || send.isPending}
              placeholder="Final design approval"
            />
          </FormRow>
          <FormRow htmlFor="a-desc" label="Description">
            <Input
              id="a-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={create.isPending || send.isPending}
            />
          </FormRow>

          <div className="grid grid-cols-2 gap-3">
            <FormRow label="Policy">
              <select
                value={policy}
                onChange={(e) => setPolicy(e.target.value as ApprovalPolicy)}
                disabled={create.isPending || send.isPending}
                className="h-9 w-full rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 text-sm"
              >
                <option value="unanimous">Unanimous (default)</option>
                <option value="single">Single</option>
                <option value="majority">Majority</option>
                <option value="quorum">Quorum</option>
                <option value="sequential">Sequential</option>
              </select>
            </FormRow>
            {policy === 'quorum' && (
              <FormRow label="Quorum minimum" required>
                <Input
                  type="number"
                  value={quorumMin}
                  onChange={(e) => setQuorumMin(e.target.value)}
                  min={1}
                  disabled={create.isPending || send.isPending}
                />
              </FormRow>
            )}
            <FormRow label="Due date">
              <Input
                type="datetime-local"
                value={dueAt}
                onChange={(e) => setDueAt(e.target.value)}
                disabled={create.isPending || send.isPending}
              />
            </FormRow>
            <FormRow label="Expires at (hard deadline)">
              <Input
                type="datetime-local"
                value={expiresAt}
                onChange={(e) => setExpiresAt(e.target.value)}
                disabled={create.isPending || send.isPending}
              />
            </FormRow>
          </div>

          <FormRow label={`Approvers (${rosterSize} selected)`} required>
            <div className="max-h-56 overflow-y-auto rounded-[--radius-md] border border-[--color-border] p-2">
              {(raw.data ?? []).length === 0 ? (
                <p className="p-2 text-xs text-[--color-text-subtle]">No participants yet.</p>
              ) : (
                (raw.data ?? []).map((r) => {
                  const key = rowKey(r)
                  const selected = isSelected(r)
                  return (
                    <div
                      key={r.id}
                      className="flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-sm hover:bg-[--color-surface-2]"
                    >
                      <label className="flex flex-1 cursor-pointer items-center gap-2">
                        <input
                          type="checkbox"
                          checked={selected}
                          disabled={create.isPending || send.isPending}
                          onChange={() => toggleRow(r)}
                        />
                        <span className="flex-1 truncate">{displayName(r)}</span>
                        <span className="text-[10px] text-[--color-text-subtle]">
                          {r.role}
                          {r.stakeholder_id ? ' · stakeholder' : ''}
                        </span>
                      </label>
                      {selected && (
                        <div className="flex items-center gap-2 text-[10px]">
                          <label className="flex items-center gap-1">
                            <input
                              type="checkbox"
                              checked={optionalMap.has(key)}
                              onChange={(e) => {
                                const next = new Set(optionalMap)
                                if (e.target.checked) next.add(key)
                                else next.delete(key)
                                setOptionalMap(next)
                              }}
                            />
                            optional
                          </label>
                          {canAssignVeto && (
                            <label className="flex items-center gap-1">
                              <input
                                type="checkbox"
                                checked={vetoMap.has(key)}
                                onChange={(e) => {
                                  const next = new Set(vetoMap)
                                  if (e.target.checked) next.add(key)
                                  else next.delete(key)
                                  setVetoMap(next)
                                }}
                              />
                              veto
                            </label>
                          )}
                        </div>
                      )}
                    </div>
                  )
                })
              )}
            </div>
          </FormRow>

          <label className="flex items-center gap-2 text-xs">
            <input
              type="checkbox"
              checked={sendImmediately}
              onChange={(e) => setSendImmediately(e.target.checked)}
              disabled={create.isPending || send.isPending}
            />
            Send immediately (notify approvers)
          </label>

          {error && <p className="text-xs text-[--color-danger]">{error}</p>}

          <DialogFooter>
            <Button
              type="button"
              variant="secondary"
              size="sm"
              onClick={() => onOpenChange(false)}
              disabled={create.isPending || send.isPending}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              size="sm"
              disabled={create.isPending || send.isPending}
            >
              {create.isPending || send.isPending
                ? 'Creating…'
                : sendImmediately
                  ? 'Create & send'
                  : 'Create draft'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
