import * as React from 'react'
import { useNavigate, useParams } from 'react-router'
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
import { useCreateReview } from './mutations'
import type { ReviewPolicy } from './queries'

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
function profileId(r: RawParticipantRow): string | null {
  return r.workspace_member?.profile?.id ?? r.stakeholder?.profile?.id ?? null
}

export function CreateReviewDialog({
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
  const [coordinatorProfileId, setCoordinatorProfileId] = React.useState<string | null>(null)
  const [policy, setPolicy] = React.useState<ReviewPolicy>('parallel')
  const [quorumMin, setQuorumMin] = React.useState('')
  const [requireCommentsResolved, setRequireCommentsResolved] = React.useState(false)
  const [dueAt, setDueAt] = React.useState('')
  const [openImmediately, setOpenImmediately] = React.useState(true)
  const [error, setError] = React.useState<string | undefined>()

  const raw = useRawParticipants(projectId)
  const create = useCreateReview()

  React.useEffect(() => {
    if (!open) {
      setTitle('')
      setDescription('')
      setSelectedWm(new Set())
      setSelectedSh(new Set())
      setCoordinatorProfileId(null)
      setPolicy('parallel')
      setQuorumMin('')
      setRequireCommentsResolved(false)
      setDueAt('')
      setOpenImmediately(true)
      setError(undefined)
    }
  }, [open])

  const rosterSize = selectedWm.size + selectedSh.size

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!title.trim()) {
      setError('Title is required.')
      return
    }
    if (openImmediately && rosterSize < 1) {
      setError('At least one reviewer is required to open the review immediately.')
      return
    }
    if (policy === 'quorum' && (!quorumMin || Number(quorumMin) <= 0)) {
      setError('Quorum requires a positive minimum.')
      return
    }
    setError(undefined)

    try {
      const id = await create.mutateAsync({
        workspaceId,
        projectId,
        designAssetId,
        versionId,
        title,
        description: description.trim() || null,
        reviewerWmIds: Array.from(selectedWm),
        reviewerShIds: Array.from(selectedSh),
        dueAt: dueAt ? new Date(dueAt).toISOString() : null,
        open: openImmediately,
        coordinatorProfileId,
        policy,
        quorumMin: policy === 'quorum' ? Number(quorumMin) : null,
        requireCommentsResolved,
      })
      onOpenChange(false)
      navigate(`/workspace/${workspaceId}/project/${projectId}/review/${id}`)
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

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>New review</DialogTitle>
          <DialogDescription>
            Reviews target a published version. Choose reviewers, policy, and coordinator.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="r-title" label="Title" required>
            <Input
              id="r-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              autoFocus
              disabled={create.isPending}
              placeholder="Kitchen review, Round 1"
            />
          </FormRow>
          <FormRow htmlFor="r-desc" label="Description">
            <Input
              id="r-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={create.isPending}
            />
          </FormRow>

          <div className="grid grid-cols-2 gap-3">
            <FormRow label="Policy">
              <select
                value={policy}
                onChange={(e) => setPolicy(e.target.value as ReviewPolicy)}
                disabled={create.isPending}
                className="h-9 w-full rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 text-sm"
              >
                <option value="parallel">Parallel</option>
                <option value="sequential">Sequential</option>
                <option value="quorum">Quorum</option>
              </select>
            </FormRow>
            {policy === 'quorum' && (
              <FormRow label="Quorum minimum" required>
                <Input
                  type="number"
                  value={quorumMin}
                  onChange={(e) => setQuorumMin(e.target.value)}
                  min={1}
                  disabled={create.isPending}
                />
              </FormRow>
            )}
            <FormRow label="Due date">
              <Input
                type="datetime-local"
                value={dueAt}
                onChange={(e) => setDueAt(e.target.value)}
                disabled={create.isPending}
              />
            </FormRow>
          </div>

          <FormRow label="Coordinator" hint="Defaults to you if unset.">
            <select
              value={coordinatorProfileId ?? ''}
              onChange={(e) => setCoordinatorProfileId(e.target.value || null)}
              disabled={create.isPending}
              className="h-9 w-full rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-3 text-sm"
            >
              <option value="">— (defaults to owner)</option>
              {(raw.data ?? [])
                .map((r) => ({ r, pid: profileId(r) }))
                .filter((x) => x.pid)
                .map(({ r, pid }) => (
                  <option key={r.id} value={pid!}>
                    {displayName(r)}
                    {r.stakeholder_id ? ' (stakeholder)' : ''}
                  </option>
                ))}
            </select>
          </FormRow>

          <FormRow label={`Reviewers (${rosterSize} selected)`} required={openImmediately}>
            <div className="max-h-48 overflow-y-auto rounded-[--radius-md] border border-[--color-border] p-2">
              {(raw.data ?? []).length === 0 ? (
                <p className="p-2 text-xs text-[--color-text-subtle]">No participants yet.</p>
              ) : (
                (raw.data ?? []).map((r) => {
                  const kind = r.workspace_member_id ? 'member' : 'stakeholder'
                  const selected = r.workspace_member_id
                    ? selectedWm.has(r.workspace_member_id)
                    : r.stakeholder_id
                      ? selectedSh.has(r.stakeholder_id)
                      : false
                  return (
                    <label
                      key={r.id}
                      className="flex cursor-pointer items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-sm hover:bg-[--color-surface-2]"
                    >
                      <input
                        type="checkbox"
                        checked={selected}
                        disabled={create.isPending}
                        onChange={() => toggleRow(r)}
                      />
                      <span className="flex-1 truncate">{displayName(r)}</span>
                      <span className="text-[10px] text-[--color-text-subtle]">
                        {r.role}
                        {kind === 'stakeholder' ? ' · stakeholder' : ''}
                      </span>
                    </label>
                  )
                })
              )}
            </div>
          </FormRow>

          <div className="space-y-1 text-xs">
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={requireCommentsResolved}
                onChange={(e) => setRequireCommentsResolved(e.target.checked)}
                disabled={create.isPending}
              />
              Require all review comments resolved before completion
            </label>
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={openImmediately}
                onChange={(e) => setOpenImmediately(e.target.checked)}
                disabled={create.isPending}
              />
              Open immediately (notify reviewers)
            </label>
          </div>

          {error && <p className="text-xs text-[--color-danger]">{error}</p>}

          <DialogFooter>
            <Button
              type="button"
              variant="secondary"
              size="sm"
              onClick={() => onOpenChange(false)}
              disabled={create.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" size="sm" disabled={create.isPending}>
              {create.isPending
                ? 'Creating…'
                : openImmediately
                  ? 'Create & open'
                  : 'Create draft'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

// Silence "unused import" if only imported for type-inference in future usage.
void useParams
