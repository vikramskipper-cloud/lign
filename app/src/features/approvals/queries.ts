import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export type ApprovalStatus =
  | 'draft'
  | 'pending'
  | 'in_progress'
  | 'approved'
  | 'rejected'
  | 'expired'
  | 'cancelled'
  | 'superseded'

export type ApprovalPolicy =
  | 'single'
  | 'unanimous'
  | 'majority'
  | 'quorum'
  | 'sequential'
  // Legacy (read-only compatibility)
  | 'any'
  | 'all'

export type ApprovalDecision = 'approved' | 'rejected' | 'abstained'

export type ApprovalDashboardView =
  | 'awaiting_me'
  | 'awaiting_others'
  | 'approved'
  | 'rejected'
  | 'expired_cancelled'
  | 'recent'
  | 'bookmarks'

export interface ApprovalDashboardRow {
  out_id: string
  out_workspace_id: string
  out_project_id: string
  out_design_asset_id: string
  out_version_id: string
  out_title: string | null
  out_description: string | null
  out_status: ApprovalStatus
  out_policy: ApprovalPolicy
  out_quorum_min: number | null
  out_root_approval_request_id: string | null
  out_supersedes_approval_request_id: string | null
  out_related_review_id: string | null
  out_created_by_profile_id: string
  out_due_at: string | null
  out_expires_at: string | null
  out_sent_at: string | null
  out_outcome_at: string | null
  out_created_at: string
  out_updated_at: string
  out_pending_count: number
  out_approved_count: number
  out_rejected_count: number
  out_abstained_count: number
  out_total_approver_count: number
  out_has_veto_approver: boolean
  out_overdue_flag: boolean
  out_my_slot_status: ApprovalDecision | null
}

export interface ApprovalDashboardFilters {
  status?: ApprovalStatus[]
  policy?: ApprovalPolicy[]
  requesterIds?: string[]
  approverProfileIds?: string[]
}

export function useApprovalsDashboard(
  wsId: string | undefined,
  projId: string | null,
  view: ApprovalDashboardView,
  filters: ApprovalDashboardFilters,
) {
  return useQuery({
    queryKey: wsId
      ? qk.approvalsList({ wsId, projId }, view, { ...filters })
      : ['approvals', 'list', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<ApprovalDashboardRow[]> => {
      const { data, error } = await supabase.rpc('list_approvals_dashboard', {
        p_ws_id: wsId as string,
        p_proj_id: projId,
        p_view: view,
        p_status_filter: filters.status ?? null,
        p_policy_filter: filters.policy ?? null,
        p_requester_ids: filters.requesterIds ?? null,
        p_approver_profile_ids: filters.approverProfileIds ?? null,
        p_limit: 100,
      })
      if (error) throw error
      return (data ?? []) as ApprovalDashboardRow[]
    },
  })
}

export interface ApprovalSlot {
  id: string
  workspace_member_id: string | null
  stakeholder_id: string | null
  required: boolean
  veto_power: boolean
  sort_order: number
  removed_at: string | null
  removed_reason: string | null
  created_at: string
  updated_at: string
  display_name: string | null
  avatar_url: string | null
  profile_id: string | null
  identity: 'member' | 'stakeholder'
  response: {
    id: string
    decision: ApprovalDecision
    comment: string | null
    responded_at: string
    is_veto_cast: boolean
  } | null
}

export interface ApprovalResponseRow {
  id: string
  approver_slot_id: string
  responder_profile_id: string
  decision: ApprovalDecision | 'changes_requested'
  comment: string | null
  responded_at: string
  is_veto_cast: boolean
  decision_metadata: Record<string, unknown> | null
}

export interface ApprovalDetail {
  request: {
    id: string
    workspace_id: string
    project_id: string
    design_asset_id: string
    version_id: string
    policy: ApprovalPolicy
    status: ApprovalStatus
    title: string | null
    description: string | null
    due_at: string | null
    sent_at: string | null
    outcome_at: string | null
    outcome_actor_profile_id: string | null
    outcome_note: string | null
    created_by_profile_id: string
    created_at: string
    updated_at: string
    expires_at: string | null
    related_review_id: string | null
    supersedes_approval_request_id: string | null
    root_approval_request_id: string | null
    quorum_min: number | null
    cancellation_reason: string | null
  }
  slots: ApprovalSlot[]
  responses: ApprovalResponseRow[]
  metrics: {
    response_distribution: {
      approved: number
      rejected: number
      abstained: number
      pending: number
    }
    has_veto_cast: boolean
    time_to_first_response: number | null
    time_to_outcome: number | null
  }
  chain_position: {
    root_approval_request_id: string | null
    is_latest: boolean
    prior_request_id: string | null
    next_request_id: string | null
  }
}

export function useApprovalDetail(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.approvalRequest(id) : ['approval', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ApprovalDetail | null> => {
      const { data, error } = await supabase.rpc('get_approval', {
        p_approval_request_id: id as string,
      })
      if (error) throw error
      return (data as ApprovalDetail | null) ?? null
    },
  })
}

export interface ApprovalChainRow {
  out_id: string
  out_status: ApprovalStatus
  out_title: string | null
  out_policy: ApprovalPolicy
  out_supersedes_approval_request_id: string | null
  out_created_at: string
  out_outcome_at: string | null
  out_approved_count: number
  out_rejected_count: number
  out_total_count: number
}

export function useApprovalChain(rootId: string | undefined) {
  return useQuery({
    queryKey: rootId ? qk.approvalChain(rootId) : ['approval-chain', 'none'],
    enabled: Boolean(rootId),
    queryFn: async (): Promise<ApprovalChainRow[]> => {
      const { data, error } = await supabase.rpc('get_approval_chain', {
        p_root_approval_request_id: rootId as string,
      })
      if (error) throw error
      return (data ?? []) as ApprovalChainRow[]
    },
  })
}

export interface ApprovalReadiness {
  has_approved: boolean
  latest_outcome: {
    status: ApprovalStatus
    outcome_at: string | null
    request_id: string
  } | null
  blocking_requests: string[]
}

export function useApprovalReadiness(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId ? qk.approvalReadiness(versionId) : ['approval', 'readiness', 'none'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<ApprovalReadiness | null> => {
      const { data, error } = await supabase.rpc('get_approval_readiness', {
        p_version_id: versionId as string,
      })
      if (error) throw error
      return (data as ApprovalReadiness | null) ?? null
    },
  })
}

export function useApprovalInboxCount(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId ? qk.approvalInboxCount(wsId) : ['approval-inbox-count', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<{
      awaiting_my_decision: number
      expiring_soon: number
      coordinating: number
    }> => {
      const { data, error } = await supabase.rpc('get_approval_inbox_count', {
        p_ws_id: wsId as string,
      })
      if (error) throw error
      return (data ?? { awaiting_my_decision: 0, expiring_soon: 0, coordinating: 0 }) as {
        awaiting_my_decision: number
        expiring_soon: number
        coordinating: number
      }
    },
  })
}

export function useProjectApprovalMetrics(projId: string | undefined) {
  return useQuery({
    queryKey: projId ? qk.approvalMetrics(`proj:${projId}`) : ['approval-metrics', 'none'],
    enabled: Boolean(projId),
    queryFn: async (): Promise<{ outstanding_count: number; overdue_count: number } | null> => {
      const { data, error } = await supabase.rpc('get_project_approval_metrics', {
        p_proj_id: projId as string,
      })
      if (error) throw error
      return (data as { outstanding_count: number; overdue_count: number } | null) ?? null
    },
  })
}

export function useApprovalsForVersion(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId ? qk.approvalsForVersion(versionId) : ['approvals', 'for-version', 'none'],
    enabled: Boolean(versionId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_approvals_for_version', {
        p_version_id: versionId as string,
      })
      if (error) throw error
      return (data ?? []) as Array<{
        out_id: string
        out_title: string | null
        out_status: ApprovalStatus
        out_policy: ApprovalPolicy
        out_created_by_profile_id: string
        out_created_at: string
        out_outcome_at: string | null
        out_expires_at: string | null
      }>
    },
  })
}
