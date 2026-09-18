import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import {
  invalidateApprovalsLists,
  invalidateApproval,
  invalidateApprovalInbox,
} from '@/features/shared/invalidate'
import { qk } from '@/lib/queryKeys'
import type { ApprovalDecision, ApprovalPolicy } from './queries'

/**
 * APP 007 approval mutations. All mutations are round-trip (no optimistic
 * updates); response casts are deliberately non-optimistic because outcome
 * computation is authoritative on the server.
 */

export interface CreateApprovalDraftInput {
  workspaceId: string
  projectId: string
  designAssetId: string
  versionId: string
  policy: ApprovalPolicy
  approverWmIds?: string[]
  approverShIds?: string[]
  approverRequired?: boolean[]
  approverVetoPower?: boolean[]
  approverSortOrder?: number[]
  title?: string | null
  description?: string | null
  dueAt?: string | null
  expiresAt?: string | null
  quorumMin?: number | null
  relatedReviewId?: string | null
}

export function useCreateApprovalDraft() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: CreateApprovalDraftInput): Promise<string> => {
      const { data, error } = await supabase.rpc('create_approval_draft', {
        p_project_id: input.projectId,
        p_design_asset_id: input.designAssetId,
        p_version_id: input.versionId,
        p_policy: input.policy,
        p_approver_wm_ids: input.approverWmIds ?? [],
        p_approver_sh_ids: input.approverShIds ?? [],
        p_title: input.title ?? null,
        p_description: input.description ?? null,
        p_due_at: input.dueAt ?? null,
        p_quorum_min: input.quorumMin ?? null,
        p_expires_at: input.expiresAt ?? null,
        p_related_review_id: input.relatedReviewId ?? null,
        p_approver_required: input.approverRequired ?? [],
        p_approver_veto_power: input.approverVetoPower ?? [],
        p_approver_sort_order: input.approverSortOrder ?? [],
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Approval draft created')
      invalidateApprovalsLists(qc, input.workspaceId, input.projectId)
      invalidateApprovalInbox(qc, input.workspaceId)
      qc.invalidateQueries({ queryKey: qk.approvalsForVersion(input.versionId) })
      qc.invalidateQueries({ queryKey: qk.approvalReadiness(input.versionId) })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useSendApprovalRequest(wsId: string, projId: string, versionId?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (requestId: string): Promise<string> => {
      const { data, error } = await supabase.rpc('send_approval_request', {
        p_approval_request_id: requestId,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_d, requestId) => {
      toast.success('Approval sent')
      invalidateApproval(qc, requestId, undefined, versionId)
      invalidateApprovalsLists(qc, wsId, projId)
      invalidateApprovalInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface RespondToApprovalInput {
  slotId: string
  decision: ApprovalDecision
  comment: string
  isVetoCast?: boolean
}

export function useRespondToApproval(
  wsId: string,
  projId: string,
  requestId: string,
  rootId?: string,
  versionId?: string,
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: RespondToApprovalInput) => {
      const { error } = await supabase.rpc('respond_to_approval', {
        p_approver_slot_id: input.slotId,
        p_decision: input.decision,
        p_comment: input.comment,
        p_is_veto_cast: input.isVetoCast ?? false,
      })
      if (error) throw error
    },
    onSuccess: (_d, input) => {
      toast.success(
        input.decision === 'approved'
          ? 'Approved'
          : input.decision === 'rejected'
            ? 'Rejected'
            : 'Abstained',
      )
      invalidateApproval(qc, requestId, rootId, versionId)
      invalidateApprovalsLists(qc, wsId, projId)
      invalidateApprovalInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useCancelApproval(
  wsId: string,
  projId: string,
  requestId: string,
  rootId?: string,
  versionId?: string,
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { reason: string }) => {
      const { error } = await supabase.rpc('cancel_approval', {
        p_approval_request_id: requestId,
        p_reason: input.reason,
        p_cancellation_reason: input.reason,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Approval cancelled')
      invalidateApproval(qc, requestId, rootId, versionId)
      invalidateApprovalsLists(qc, wsId, projId)
      invalidateApprovalInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useExpireApproval(
  wsId: string,
  projId: string,
  requestId: string,
  rootId?: string,
  versionId?: string,
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { reason?: string | null }) => {
      const { error } = await supabase.rpc('expire_approval', {
        p_approval_request_id: requestId,
        p_reason: input.reason ?? null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Approval expired')
      invalidateApproval(qc, requestId, rootId, versionId)
      invalidateApprovalsLists(qc, wsId, projId)
      invalidateApprovalInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface SupersedeApprovalInput {
  oldRequestId: string
  newTargetVersionId: string
  policy: ApprovalPolicy
  approverWmIds: string[]
  approverShIds: string[]
  approverRequired?: boolean[]
  approverVetoPower?: boolean[]
  approverSortOrder?: number[]
  quorumMin?: number | null
  dueAt?: string | null
  expiresAt?: string | null
  relatedReviewId?: string | null
  note?: string | null
  title?: string | null
  description?: string | null
}

export function useSupersedeApproval(
  wsId: string,
  projId: string,
  rootId?: string,
  versionId?: string,
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: SupersedeApprovalInput): Promise<string> => {
      const { data, error } = await supabase.rpc('supersede_approval_request', {
        p_old_request_id: input.oldRequestId,
        p_new_target_version_id: input.newTargetVersionId,
        p_policy: input.policy,
        p_approver_wm_ids: input.approverWmIds,
        p_approver_sh_ids: input.approverShIds,
        p_quorum_min: input.quorumMin ?? null,
        p_due_at: input.dueAt ?? null,
        p_expires_at: input.expiresAt ?? null,
        p_related_review_id: input.relatedReviewId ?? null,
        p_approver_required: input.approverRequired ?? [],
        p_approver_veto_power: input.approverVetoPower ?? [],
        p_approver_sort_order: input.approverSortOrder ?? [],
        p_note: input.note ?? null,
        p_title: input.title ?? null,
        p_description: input.description ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (newId, input) => {
      toast.success('New approval created')
      invalidateApproval(qc, input.oldRequestId, rootId, versionId)
      invalidateApproval(qc, newId, rootId, input.newTargetVersionId)
      invalidateApprovalsLists(qc, wsId, projId)
      invalidateApprovalInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useAddApprover(wsId: string, projId: string, requestId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      wmId?: string | null
      shId?: string | null
      required: boolean
      vetoPower: boolean
      sortOrder: number
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('add_approver', {
        p_approval_request_id: requestId,
        p_wm_id: input.wmId ?? null,
        p_sh_id: input.shId ?? null,
        p_required: input.required,
        p_veto_power: input.vetoPower,
        p_sort_order: input.sortOrder,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => {
      toast.success('Approver added')
      invalidateApproval(qc, requestId)
      invalidateApprovalsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useRemoveApprover(wsId: string, projId: string, requestId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { slotId: string; reason: string }) => {
      const { error } = await supabase.rpc('remove_approver', {
        p_approver_slot_id: input.slotId,
        p_reason: input.reason,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Approver removed')
      invalidateApproval(qc, requestId)
      invalidateApprovalsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useSetApproverRequired(requestId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { slotId: string; required: boolean }) => {
      const { error } = await supabase.rpc('set_approver_required', {
        p_approver_slot_id: input.slotId,
        p_required: input.required,
      })
      if (error) throw error
    },
    onSuccess: () => invalidateApproval(qc, requestId),
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useSetApproverVetoPower(requestId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { slotId: string; vetoPower: boolean }) => {
      const { error } = await supabase.rpc('set_approver_veto_power', {
        p_approver_slot_id: input.slotId,
        p_veto_power: input.vetoPower,
      })
      if (error) throw error
    },
    onSuccess: () => invalidateApproval(qc, requestId),
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useToggleApprovalBookmark(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { subjectId: string }): Promise<boolean> => {
      const { data, error } = await supabase.rpc('toggle_bookmark', {
        p_subject_kind: 'approval_request',
        p_subject_id: input.subjectId,
        p_workspace_id: wsId,
      })
      if (error) throw error
      return data as boolean
    },
    onSuccess: (bookmarked) => {
      toast.success(bookmarked ? 'Bookmarked' : 'Removed bookmark')
      qc.invalidateQueries({ queryKey: qk.bookmarks(wsId, 'approval_request') })
      invalidateApprovalsLists(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}
