import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

/**
 * APP 008 — Requirements read hooks.
 *
 * Every hook wraps a SECURITY DEFINER RPC that re-checks requirement.view
 * server-side. Cursor pagination is opaque (updated_at desc, id desc).
 */

export type RequirementStatus = 'draft' | 'active' | 'superseded' | 'archived'
export type RequirementPriority =
  | 'critical'
  | 'high'
  | 'medium'
  | 'low'
  | 'informational'
export type RequirementSourceKind =
  | 'client'
  | 'consultant'
  | 'regulatory'
  | 'internal_team'
  | 'qa'
  | 'procurement'
  | 'manufacturing'
  | 'safety'
  | 'contractual'
  | 'other'
export type RequirementCategoryKind =
  | 'functional'
  | 'non_functional'
  | 'regulatory'
  | 'contractual'
  | 'technical'
  | 'aesthetic'
  | 'sustainability'
  | 'safety'
  | 'operational'
  | 'other'
export type AssessmentStatus =
  | 'satisfied'
  | 'partial'
  | 'not_satisfied'
  | 'not_applicable'

export type RequirementsDashboardView =
  | 'all_active'
  | 'assigned_to_me'
  | 'recently_updated'
  | 'by_status'
  | 'by_priority'
  | 'by_source'
  | 'needs_assessment'
  | 'overdue_critical'
  | 'bookmarks'
  | 'archived'
  | 'superseded'
  | 'compliance'
  | 'all'

export interface ApplicabilitySummary {
  scope: 'project_wide' | 'asset_scoped'
  asset_count: number
}

export interface AssessmentCoverage {
  applicable_versions_count: number
  satisfied_count: number
  coverage_pct: number
  latest_version_assessed: boolean
}

export interface RequirementDashboardRow {
  requirement_id: string
  code: string
  title: string
  status: RequirementStatus
  priority: RequirementPriority | null
  source_kind: RequirementSourceKind | null
  category_kind: RequirementCategoryKind | null
  owner_profile_id: string | null
  updated_at: string
  applicability_summary: ApplicabilitySummary
  assessment_coverage: AssessmentCoverage
  project_id: string
  project_name: string | null
  workspace_id: string
  due_at: string | null
}

export interface DashboardCursor {
  updated_at: string
  id: string
}

export interface DashboardPage {
  rows: RequirementDashboardRow[]
  next_cursor: DashboardCursor | null
}

export interface RequirementsDashboardFilters {
  status?: RequirementStatus[]
  priority?: RequirementPriority[]
  source?: RequirementSourceKind[]
  category?: RequirementCategoryKind[]
  scope?: 'project_wide' | 'asset_scoped' | null
  ownerIds?: string[]
  search?: string
  cursor?: DashboardCursor | null
  savedViewId?: string | null
  limit?: number
}

export function useRequirementsDashboard(
  wsId: string | undefined,
  projId: string | null,
  view: RequirementsDashboardView,
  filters: RequirementsDashboardFilters,
) {
  return useQuery({
    queryKey: wsId
      ? qk.requirementsList({ wsId, projId }, view, { ...filters })
      : ['requirements', 'list', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<DashboardPage> => {
      const { data, error } = await supabase.rpc('list_requirements_dashboard', {
        p_ws_id: wsId as string,
        p_proj_id: projId,
        p_view: view,
        p_status_filter: filters.status ?? null,
        p_priority_filter: filters.priority ?? null,
        p_source_filter: filters.source ?? null,
        p_category_filter: filters.category ?? null,
        p_scope_filter: filters.scope ?? null,
        p_owner_ids: filters.ownerIds ?? null,
        p_search: filters.search ?? null,
        p_cursor_updated_at: filters.cursor?.updated_at ?? null,
        p_cursor_id: filters.cursor?.id ?? null,
        p_limit: filters.limit ?? 50,
        p_saved_view_id: filters.savedViewId ?? null,
      })
      if (error) throw error
      return (data as DashboardPage) ?? { rows: [], next_cursor: null }
    },
  })
}

export interface RequirementRow {
  id: string
  workspace_id: string
  project_id: string
  parent_requirement_id: string | null
  code: string
  title: string
  description: string | null
  category: string | null
  source: string | null
  source_ref: string | null
  status: RequirementStatus
  superseded_by_requirement_id: string | null
  archived_at: string | null
  created_by_profile_id: string | null
  created_at: string
  updated_at: string
  priority: RequirementPriority | null
  source_kind: RequirementSourceKind | null
  category_kind: RequirementCategoryKind | null
  owner_profile_id: string | null
  verification_method:
    | 'inspection'
    | 'test'
    | 'analysis'
    | 'demonstration'
    | null
  due_at: string | null
}

export interface RequirementDetail {
  requirement: RequirementRow
  sub_requirements: RequirementRow[]
  applicability_summary: {
    is_project_wide: boolean
    asset_count: number
    asset_ids: string[]
  }
  assessment_summary: {
    versions_applicable: number
    versions_assessed: number
    latest_status_per_asset: Record<string, AssessmentStatus | 'unassessed'>
  }
  metrics: {
    coverage_pct: number
    days_since_last_assessment: number | null
    days_until_due: number | null
  }
  chain_position: {
    supersedes: string | null
    superseded_by: string | null
    chain_depth: number
  }
}

export function useRequirement(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.requirement(id) : ['requirement', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<RequirementDetail | null> => {
      const { data, error } = await supabase.rpc('get_requirement', {
        p_requirement_id: id as string,
      })
      if (error) throw error
      return (data as RequirementDetail | null) ?? null
    },
  })
}

export interface RequirementChainRow {
  requirement_id: string
  code: string
  title: string
  status: RequirementStatus
  superseded_by_requirement_id: string | null
  is_current: boolean
}

export function useRequirementChain(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.requirementChain(id) : ['requirement-chain', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<RequirementChainRow[]> => {
      const { data, error } = await supabase.rpc('get_requirement_chain', {
        p_requirement_id: id as string,
      })
      if (error) throw error
      return (data ?? []) as RequirementChainRow[]
    },
  })
}

export interface RequirementTrace {
  requirement: RequirementRow
  applicable_assets: Array<{
    design_asset_id: string
    name: string | null
    project_id: string
  }>
  is_project_wide: boolean
  sub_requirements: Array<{
    id: string
    code: string
    title: string
    status: RequirementStatus
    priority: RequirementPriority | null
  }>
  assessments: Array<{
    asset_version_id: string
    asset_id: string
    version_number: number | null
    status: AssessmentStatus
    note: string | null
    assessed_at: string
    assessed_by_profile_id: string | null
  }>
  related_changes: Array<{
    change_id: string
    kind: string
    created_at: string
    subject_label: string | null
  }>
  related_decisions: Array<{
    decision_id: string
    subject_kind: string
    subject_id: string | null
    created_at: string
    decision_reason_snippet: string
  }>
  discussion_count: number
  approval_requests: Array<{
    approval_request_id: string
    status: string
    outcome_at: string | null
    root_approval_request_id: string | null
  }>
  supersession_chain: RequirementChainRow[]
  metrics: {
    coverage_pct: number
    critical_unsatisfied_count: number
    unassessed_on_latest_count: number
  }
}

export function useRequirementTrace(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.requirementTrace(id) : ['requirement-trace', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<RequirementTrace | null> => {
      const { data, error } = await supabase.rpc('get_requirement_trace', {
        p_requirement_id: id as string,
      })
      if (error) throw error
      return (data as RequirementTrace | null) ?? null
    },
  })
}

export function useRequirementInboxCount(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId
      ? qk.requirementInboxCount(wsId)
      : ['requirement-inbox-count', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<{
      assigned_to_me: number
      overdue_critical: number
      needs_assessment: number
    }> => {
      const { data, error } = await supabase.rpc('get_requirement_inbox_count', {
        p_ws_id: wsId as string,
      })
      if (error) throw error
      return (
        (data as {
          assigned_to_me: number
          overdue_critical: number
          needs_assessment: number
        } | null) ?? { assigned_to_me: 0, overdue_critical: 0, needs_assessment: 0 }
      )
    },
  })
}

export interface ProjectRequirementMetrics {
  total_count: number
  by_status: Partial<Record<RequirementStatus, number>>
  by_priority: Partial<Record<RequirementPriority | 'unset', number>>
  by_source: Record<string, number>
  unassessed_on_latest_count: number
  critical_unsatisfied_count: number
  overdue_count: number
  coverage_rate: number
  trailing_30d_creation_rate: number
  trailing_30d_assessment_activity_rate: number
}

export function useProjectRequirementMetrics(projId: string | undefined) {
  return useQuery({
    queryKey: projId
      ? qk.requirementMetrics(`proj:${projId}`)
      : ['requirement-metrics', 'none'],
    enabled: Boolean(projId),
    queryFn: async (): Promise<ProjectRequirementMetrics | null> => {
      const { data, error } = await supabase.rpc('get_project_requirement_metrics', {
        p_project_id: projId as string,
      })
      if (error) throw error
      return (data as ProjectRequirementMetrics | null) ?? null
    },
  })
}

export interface WorkspaceRequirementMetrics {
  total_active: number
  by_status: Partial<Record<RequirementStatus, number>>
  by_priority: Partial<Record<RequirementPriority | 'unset', number>>
  top5_projects_by_critical_unsatisfied: Array<{
    project_id: string
    project_name: string | null
    cnt: number
  }>
  top5_owners_by_open_load: Array<{
    owner_profile_id: string
    display_name: string | null
    cnt: number
  }>
  overdue_count_across_workspace: number
}

export function useWorkspaceRequirementMetrics(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId
      ? qk.requirementMetrics(`ws:${wsId}`)
      : ['requirement-metrics', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<WorkspaceRequirementMetrics | null> => {
      const { data, error } = await supabase.rpc(
        'get_workspace_requirement_metrics',
        { p_ws_id: wsId as string },
      )
      if (error) throw error
      return (data as WorkspaceRequirementMetrics | null) ?? null
    },
  })
}

export interface ReleaseReadiness {
  applicable_count: number
  satisfied_count: number
  partial_count: number
  not_satisfied_count: number
  unassessed_count: number
  critical_unsatisfied_count: number
  critical_unassessed_count: number
}

export function useReleaseReadinessForVersion(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId
      ? qk.releaseReadinessForVersion(versionId)
      : ['requirements', 'release-readiness', 'none'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<ReleaseReadiness | null> => {
      const { data, error } = await supabase.rpc(
        'get_release_readiness_for_version',
        { p_asset_version_id: versionId as string },
      )
      if (error) throw error
      return (data as ReleaseReadiness | null) ?? null
    },
  })
}

/** Frozen APP 003/004 read: applicable requirements for a design_asset. */
export interface ApplicableRequirementRow {
  out_requirement_id: string
  out_code: string
  out_title: string
  out_status: RequirementStatus
  out_parent_requirement_id: string | null
  out_is_project_wide: boolean
  out_assessment_status: AssessmentStatus | null
  out_assessed_at: string | null
  out_assessed_by_profile_id: string | null
}

export function useApplicableRequirementsForAsset(
  assetId: string | undefined,
  versionId: string | null | undefined,
) {
  return useQuery({
    queryKey: assetId
      ? qk.applicableRequirementsForAsset(assetId, versionId ?? null)
      : ['requirements', 'for-asset', 'none'],
    enabled: Boolean(assetId),
    queryFn: async (): Promise<ApplicableRequirementRow[]> => {
      const { data, error } = await supabase.rpc('list_applicable_requirements', {
        p_design_asset_id: assetId as string,
        p_asset_version_id: versionId ?? null,
      })
      if (error) throw error
      return (data ?? []) as ApplicableRequirementRow[]
    },
  })
}

/** Frozen list_project_requirements — used by the applicability editor's picker source. */
export interface ProjectRequirementRow {
  out_requirement_id: string
  out_code: string
  out_title: string
  out_description: string | null
  out_category: string | null
  out_source: string | null
  out_source_ref: string | null
  out_status: RequirementStatus
  out_parent_requirement_id: string | null
  out_superseded_by_requirement_id: string | null
  out_archived_at: string | null
  out_created_by_profile_id: string | null
  out_created_at: string
  out_updated_at: string
}

export function useListProjectRequirements(
  projectId: string | undefined,
  workspaceId: string | undefined,
) {
  return useQuery({
    queryKey: projectId
      ? ['requirements', 'project-list', projectId, workspaceId ?? null]
      : ['requirements', 'project-list', 'none'],
    enabled: Boolean(projectId && workspaceId),
    queryFn: async (): Promise<ProjectRequirementRow[]> => {
      const { data, error } = await supabase.rpc('list_project_requirements', {
        p_project_id: projectId as string,
        p_workspace_id: workspaceId as string,
        p_include_archived: false,
        p_include_superseded: true,
      })
      if (error) throw error
      return (data ?? []) as ProjectRequirementRow[]
    },
  })
}

/** Discussions tab: comments where target_requirement_id = <id>. */
export interface RequirementDiscussionRow {
  id: string
  workspace_id: string
  parent_comment_id: string | null
  body: string
  author_profile_id: string | null
  resolved_at: string | null
  deleted_at: string | null
  target_requirement_id: string
  created_at: string
  updated_at: string
  author: { id: string; display_name: string; avatar_url: string | null } | null
}

const DISCUSSION_SELECT = `
  id, workspace_id, parent_comment_id, body, author_profile_id, resolved_at, deleted_at,
  target_requirement_id, created_at, updated_at,
  author:profiles!comments_author_profile_id_fkey ( id, display_name, avatar_url )
`

export function useRequirementDiscussions(requirementId: string | undefined) {
  return useQuery({
    queryKey: requirementId
      ? qk.requirementDiscussions(requirementId)
      : ['requirement', 'none', 'discussions'],
    enabled: Boolean(requirementId),
    queryFn: async (): Promise<RequirementDiscussionRow[]> => {
      const { data, error } = await supabase
        .from('comments')
        .select(DISCUSSION_SELECT)
        .eq('target_requirement_id', requirementId as string)
        .is('deleted_at', null)
        .order('created_at', { ascending: true })
      if (error) throw error
      return (data ?? []) as unknown as RequirementDiscussionRow[]
    },
  })
}

/** History tab: activity_events for a requirement + its assessments. */
export interface RequirementHistoryEvent {
  id: string
  event_type: string
  occurred_at: string
  actor_profile_id: string | null
  subject_label: string | null
  subject_snapshot: Record<string, unknown> | null
}

export function useRequirementHistory(requirementId: string | undefined) {
  return useQuery({
    queryKey: requirementId
      ? qk.requirementHistory(requirementId)
      : ['requirement', 'none', 'history'],
    enabled: Boolean(requirementId),
    queryFn: async (): Promise<RequirementHistoryEvent[]> => {
      // Two OR-filter reads unioned client-side. Uses `subject_snapshot->>requirement_id`
      // for assessment events. PostgREST filter with jsonb path.
      const [reqEvents, vraEvents] = await Promise.all([
        supabase
          .from('activity_events')
          .select(
            'id, event_type, occurred_at, actor_profile_id, subject_label, subject_snapshot',
          )
          .eq('subject_kind', 'requirement')
          .eq('subject_id', requirementId as string)
          .order('occurred_at', { ascending: false })
          .limit(200),
        supabase
          .from('activity_events')
          .select(
            'id, event_type, occurred_at, actor_profile_id, subject_label, subject_snapshot',
          )
          .eq('subject_kind', 'version_requirement_assessment')
          .filter('subject_snapshot->>requirement_id', 'eq', requirementId as string)
          .order('occurred_at', { ascending: false })
          .limit(200),
      ])
      if (reqEvents.error) throw reqEvents.error
      if (vraEvents.error) throw vraEvents.error
      const merged = [
        ...((reqEvents.data ?? []) as unknown as RequirementHistoryEvent[]),
        ...((vraEvents.data ?? []) as unknown as RequirementHistoryEvent[]),
      ]
      merged.sort((a, b) => b.occurred_at.localeCompare(a.occurred_at))
      return merged.slice(0, 200)
    },
  })
}
