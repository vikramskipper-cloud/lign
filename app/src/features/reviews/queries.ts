import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export type ReviewStatus =
  | 'draft'
  | 'ready_for_review'
  | 'open'
  | 'in_progress'
  | 'waiting'
  | 'completed'
  | 'cancelled'

export type ReviewPolicy = 'parallel' | 'sequential' | 'quorum'
export type ReviewerResponse = 'pending' | 'commented' | 'signed_off' | 'declined'
export type DashboardView =
  | 'assigned_to_me'
  | 'waiting_on_others'
  | 'overdue'
  | 'completed'
  | 'recent'
  | 'bookmarks'

export interface ReviewDashboardRow {
  out_id: string
  out_workspace_id: string
  out_project_id: string
  out_design_asset_id: string
  out_version_id: string
  out_title: string
  out_description: string | null
  out_status: ReviewStatus
  out_round_number: number
  out_root_review_id: string
  out_policy: ReviewPolicy
  out_created_by_profile_id: string
  out_coordinator_profile_id: string | null
  out_due_at: string | null
  out_completed_at: string | null
  out_cancelled_at: string | null
  out_created_at: string
  out_updated_at: string
  out_open_reviewer_count: number
  out_signed_off_count: number
  out_declined_count: number
  out_commented_count: number
  out_total_reviewer_count: number
  out_open_comment_count: number
  out_overdue_flag: boolean
  out_my_slot_status: ReviewerResponse | null
}

export interface DashboardFilters {
  status?: ReviewStatus[]
  ownerIds?: string[]
  reviewerProfileIds?: string[]
}

export function useReviewsDashboard(
  wsId: string | undefined,
  projId: string | null,
  view: DashboardView,
  filters: DashboardFilters,
) {
  return useQuery({
    queryKey: wsId
      ? qk.reviewsList({ wsId, projId }, view, { ...filters })
      : ['reviews', 'list', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<ReviewDashboardRow[]> => {
      const { data, error } = await supabase.rpc('list_reviews_dashboard', {
        p_ws_id: wsId as string,
        p_proj_id: projId,
        p_view: view,
        p_status_filter: filters.status ?? null,
        p_owner_ids: filters.ownerIds ?? null,
        p_reviewer_profile_ids: filters.reviewerProfileIds ?? null,
        p_limit: 100,
      })
      if (error) throw error
      return (data ?? []) as ReviewDashboardRow[]
    },
  })
}

export interface ReviewDetail {
  review: {
    id: string
    workspace_id: string
    project_id: string
    design_asset_id: string
    version_id: string
    title: string
    description: string | null
    status: ReviewStatus
    round_number: number
    parent_review_id: string | null
    root_review_id: string
    coordinator_profile_id: string | null
    policy: ReviewPolicy
    quorum_min: number | null
    require_comments_resolved: boolean
    cancellation_reason: string | null
    due_at: string | null
    completed_at: string | null
    cancelled_at: string | null
    created_by_profile_id: string
    created_at: string
    updated_at: string
  }
  participants: ReviewParticipant[]
  metrics: {
    opened_at: string | null
    first_responded_at: string | null
    first_commented_at: string | null
    open_comment_count: number
    response_distribution: {
      signed_off: number
      commented: number
      declined: number
      pending: number
    }
    newer_version_exists: boolean
  }
  chain_position: {
    round_number: number
    is_latest: boolean
    prior_review_id: string | null
    next_review_id: string | null
  }
}

export interface ReviewParticipant {
  id: string
  workspace_member_id: string | null
  stakeholder_id: string | null
  status: ReviewerResponse
  assigned_at: string
  responded_at: string | null
  required: boolean
  sequence_index: number
  removed_at: string | null
  removed_reason: string | null
  display_name: string | null
  avatar_url: string | null
  profile_id: string | null
  identity: 'member' | 'stakeholder'
}

export function useReviewDetail(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.review(id) : ['review', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReviewDetail | null> => {
      const { data, error } = await supabase.rpc('get_review', { p_review_id: id as string })
      if (error) throw error
      return (data as ReviewDetail | null) ?? null
    },
  })
}

export interface ReviewChainRow {
  out_id: string
  out_round_number: number
  out_status: ReviewStatus
  out_title: string
  out_created_at: string
  out_completed_at: string | null
  out_cancelled_at: string | null
  out_reviewer_count: number
  out_signed_off_count: number
  out_declined_count: number
}

export function useReviewChain(rootId: string | undefined) {
  return useQuery({
    queryKey: rootId ? qk.reviewChain(rootId) : ['review-chain', 'none'],
    enabled: Boolean(rootId),
    queryFn: async (): Promise<ReviewChainRow[]> => {
      const { data, error } = await supabase.rpc('get_review_chain', {
        p_root_review_id: rootId as string,
      })
      if (error) throw error
      return (data ?? []) as ReviewChainRow[]
    },
  })
}

export function useReviewInboxCount(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId ? qk.reviewInboxCount(wsId) : ['review-inbox-count', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<{
      assigned_to_me: number
      overdue: number
      coordinating: number
    }> => {
      const { data, error } = await supabase.rpc('get_review_inbox_count', {
        p_ws_id: wsId as string,
      })
      if (error) throw error
      return (data ?? { assigned_to_me: 0, overdue: 0, coordinating: 0 }) as {
        assigned_to_me: number
        overdue: number
        coordinating: number
      }
    },
  })
}

export function useProjectReviewMetrics(projId: string | undefined) {
  return useQuery({
    queryKey: projId ? qk.reviewMetrics(`proj:${projId}`) : ['review-metrics', 'none'],
    enabled: Boolean(projId),
    queryFn: async (): Promise<{ outstanding_count: number; overdue_count: number } | null> => {
      const { data, error } = await supabase.rpc('get_project_review_metrics', {
        p_proj_id: projId as string,
      })
      if (error) throw error
      return (data as { outstanding_count: number; overdue_count: number } | null) ?? null
    },
  })
}

export function useReviewsForVersion(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId
      ? ['reviews', 'for-version', versionId]
      : ['reviews', 'for-version', 'none'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<
      Array<{
        id: string
        title: string
        status: ReviewStatus
        round_number: number
        due_at: string | null
        created_by_profile_id: string
        coordinator_profile_id: string | null
      }>
    > => {
      const { data, error } = await supabase
        .from('reviews')
        .select(
          'id, title, status, round_number, due_at, created_by_profile_id, coordinator_profile_id',
        )
        .eq('version_id', versionId as string)
        .order('created_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as unknown as Array<{
        id: string
        title: string
        status: ReviewStatus
        round_number: number
        due_at: string | null
        created_by_profile_id: string
        coordinator_profile_id: string | null
      }>
    },
  })
}
