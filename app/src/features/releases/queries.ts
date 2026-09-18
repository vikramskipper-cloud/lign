import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

/**
 * APP 009 — Releases read hooks.
 *
 * Every hook wraps a SECURITY DEFINER RPC that re-checks release.view server-side.
 * Cursor pagination is opaque (released_at desc nulls last, id desc).
 */

export type ReleaseStatus =
  | 'draft'
  | 'scheduled'
  | 'released'
  | 'superseded'
  | 'withdrawn'

export type ReleaseType =
  | 'internal'
  | 'preview'
  | 'client'
  | 'regulatory'
  | 'final'
  | 'patch'
  | 'hotfix'

export const RELEASE_TYPES: ReleaseType[] = [
  'internal',
  'preview',
  'client',
  'regulatory',
  'final',
  'patch',
  'hotfix',
]

export type ReleasesDashboardView =
  | 'all'
  | 'draft'
  | 'released'
  | 'withdrawn'
  | 'discarded'
  | 'published_by_me'

export interface ReleaseDashboardRow {
  out_release_id: string
  out_workspace_id: string
  out_project_id: string
  out_project_name: string | null
  out_code: string | null
  out_name: string
  out_release_type: ReleaseType | null
  out_status: ReleaseStatus
  out_channel: string | null
  out_released_at: string | null
  out_withdrawn_at: string | null
  out_discarded_at: string | null
  out_created_by_profile_id: string | null
  out_published_by_profile_id: string | null
  out_created_at: string
  out_updated_at: string
  out_item_count: number
  out_next_cursor_at: string | null
  out_next_cursor_id: string
}

export interface ReleasesDashboardFilters {
  status?: ReleaseStatus[]
  releaseType?: ReleaseType[]
  publishedByIds?: string[]
  search?: string
  includeDiscarded?: boolean
  savedViewId?: string | null
  cursor?: { released_at: string | null; id: string } | null
  limit?: number
}

export function useReleasesDashboard(
  wsId: string | undefined,
  projId: string | null,
  view: ReleasesDashboardView,
  filters: ReleasesDashboardFilters,
) {
  return useQuery({
    queryKey: wsId
      ? qk.releasesList({ wsId, projId }, view, { ...filters })
      : ['releases', 'list', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<ReleaseDashboardRow[]> => {
      const { data, error } = await supabase.rpc('list_releases_dashboard', {
        p_ws_id: wsId as string,
        p_proj_id: projId,
        p_view: view,
        p_status_filter: filters.status ?? null,
        p_release_type_filter: filters.releaseType ?? null,
        p_published_by_ids: filters.publishedByIds ?? null,
        p_search: filters.search ?? null,
        p_include_discarded: filters.includeDiscarded ?? false,
        p_cursor_released_at: filters.cursor?.released_at ?? null,
        p_cursor_id: filters.cursor?.id ?? null,
        p_limit: filters.limit ?? 50,
        p_saved_view_id: filters.savedViewId ?? null,
      })
      if (error) throw error
      return (data ?? []) as ReleaseDashboardRow[]
    },
  })
}

export interface ReleaseDetail {
  id: string
  workspace_id: string
  project_id: string
  name: string
  notes: string | null
  channel: string | null
  release_type: ReleaseType | null
  status: ReleaseStatus
  code: string | null
  effective_at: string | null
  released_at: string | null
  withdrawn_at: string | null
  withdrawn_reason: string | null
  created_by_profile_id: string | null
  published_by_profile_id: string | null
  created_at: string
  updated_at: string
  discarded_at: string | null
  superseded_by_release_id: string | null
  root_release_id: string | null
  item_count: number
  chain_length: number
  chain_position: number
}

export function useRelease(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.release(id) : ['release', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReleaseDetail | null> => {
      const { data, error } = await supabase.rpc('get_release', {
        p_release_id: id as string,
      })
      if (error) throw error
      return (data as ReleaseDetail | null) ?? null
    },
  })
}

export interface ReleaseChainNode {
  release_id: string
  code: string | null
  name: string
  release_type: ReleaseType | null
  status: ReleaseStatus
  released_at: string | null
  withdrawn_at: string | null
  is_root: boolean
  is_head: boolean
}

export function useReleaseChain(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.releaseChain(id) : ['release-chain', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReleaseChainNode[]> => {
      const { data, error } = await supabase.rpc('get_release_chain', {
        p_release_id: id as string,
      })
      if (error) throw error
      return ((data as { nodes: ReleaseChainNode[] } | null)?.nodes ?? [])
    },
  })
}

export interface ReleaseEvidence {
  snapshot: Record<string, unknown> | null
  live_delta: { items: Array<Record<string, unknown>> }
  has_deltas: boolean
}

export function useReleaseEvidence(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.releaseEvidence(id) : ['release', 'none', 'evidence'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReleaseEvidence | null> => {
      const { data, error } = await supabase.rpc('get_release_evidence', {
        p_release_id: id as string,
      })
      if (error) throw error
      return (data as ReleaseEvidence | null) ?? null
    },
  })
}

export interface ReleaseComparison {
  this_release: ReleaseDetail | null
  compare_to: ReleaseDetail | null
  item_diff: {
    added: Array<{ design_asset_id: string; version_id: string }>
    removed: Array<{ design_asset_id: string; version_id: string }>
    changed_version: Array<{
      design_asset_id: string
      this_version_id: string
      compare_version_id: string
    }>
  }
}

export function useReleaseComparison(
  id: string | undefined,
  compareToId: string | null,
) {
  return useQuery({
    queryKey: id
      ? qk.releaseComparison(id, compareToId)
      : ['release', 'none', 'comparison'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReleaseComparison | null> => {
      const { data, error } = await supabase.rpc('get_release_comparison', {
        p_release_id: id as string,
        p_compare_to_release_id: compareToId,
      })
      if (error) throw error
      return (data as ReleaseComparison | null) ?? null
    },
  })
}

export interface ReleaseActivityRow {
  out_id: string
  out_event_type: string
  out_occurred_at: string
  out_actor_profile_id: string | null
  out_subject_kind: string
  out_subject_id: string
  out_subject_label: string | null
  out_subject_snapshot: Record<string, unknown> | null
  out_payload: Record<string, unknown> | null
}

export function useReleaseActivity(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.releaseActivity(id) : ['release', 'none', 'activity'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReleaseActivityRow[]> => {
      const { data, error } = await supabase.rpc('list_release_activity', {
        p_release_id: id as string,
        p_cursor_at: null,
        p_cursor_id: null,
        p_limit: 100,
      })
      if (error) throw error
      return (data ?? []) as ReleaseActivityRow[]
    },
  })
}

export interface ReleaseItemRow {
  out_release_item_id: string
  out_design_asset_id: string
  out_design_asset_name: string | null
  out_version_id: string
  out_version_sequence: number | null
  out_version_published_at: string | null
  out_notes: string | null
  out_sort_order: number | null
  out_approval_state: Record<string, unknown> | null
  out_requirement_readiness_summary: Record<string, unknown> | null
}

export function useReleaseItems(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.releaseItems(id) : ['release', 'none', 'items'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ReleaseItemRow[]> => {
      const { data, error } = await supabase.rpc('list_release_items', {
        p_release_id: id as string,
      })
      if (error) throw error
      return (data ?? []) as ReleaseItemRow[]
    },
  })
}

export interface ReleaseInboxCount {
  workspace_released_trailing_30d: number
  workspace_draft_count: number
  per_project: Array<{
    project_id: string
    released_trailing_30d: number
  }>
}

export function useReleaseInboxCount(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId ? qk.releaseInboxCount(wsId) : ['release-inbox-count', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<ReleaseInboxCount | null> => {
      const { data, error } = await supabase.rpc('get_release_inbox_count', {
        p_ws_id: wsId as string,
      })
      if (error) throw error
      return (data as ReleaseInboxCount | null) ?? null
    },
  })
}

export interface ProjectReleaseMetrics {
  total_draft: number
  total_released: number
  total_withdrawn: number
  released_trailing_30d: number
  released_trailing_90d: number
  by_type: Record<ReleaseType, number>
  chain_head_count: number
  discarded_count: number
}

export function useProjectReleaseMetrics(projId: string | undefined) {
  return useQuery({
    queryKey: projId
      ? qk.releaseMetrics(`proj:${projId}`)
      : ['release-metrics', 'none'],
    enabled: Boolean(projId),
    queryFn: async (): Promise<ProjectReleaseMetrics | null> => {
      const { data, error } = await supabase.rpc('get_project_release_metrics', {
        p_project_id: projId as string,
      })
      if (error) throw error
      return (data as ProjectReleaseMetrics | null) ?? null
    },
  })
}

export interface WorkspaceReleaseMetrics extends ProjectReleaseMetrics {
  per_project_top5: Array<{ project_id: string; released_trailing_30d: number }>
}

export function useWorkspaceReleaseMetrics(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId
      ? qk.releaseMetrics(`ws:${wsId}`)
      : ['release-metrics', 'none'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<WorkspaceReleaseMetrics | null> => {
      const { data, error } = await supabase.rpc('get_workspace_release_metrics', {
        p_ws_id: wsId as string,
      })
      if (error) throw error
      return (data as WorkspaceReleaseMetrics | null) ?? null
    },
  })
}

export interface ReleaseForAssetRow {
  out_release_id: string
  out_code: string | null
  out_name: string
  out_release_type: ReleaseType | null
  out_status: ReleaseStatus
  out_released_at: string | null
  out_version_id: string
  out_version_sequence: number | null
}

export function useReleasesForAsset(assetId: string | undefined) {
  return useQuery({
    queryKey: assetId ? qk.releasesForAsset(assetId) : ['releases', 'for-asset', 'none'],
    enabled: Boolean(assetId),
    queryFn: async (): Promise<ReleaseForAssetRow[]> => {
      const { data, error } = await supabase.rpc('list_releases_for_asset', {
        p_design_asset_id: assetId as string,
      })
      if (error) throw error
      return (data ?? []) as ReleaseForAssetRow[]
    },
  })
}

export function useReleasesForVersion(versionId: string | undefined) {
  return useQuery({
    queryKey: versionId
      ? qk.releasesForVersion(versionId)
      : ['releases', 'for-version', 'none'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<ReleaseForAssetRow[]> => {
      const { data, error } = await supabase.rpc('list_releases_for_version', {
        p_version_id: versionId as string,
      })
      if (error) throw error
      return (data ?? []) as ReleaseForAssetRow[]
    },
  })
}

export interface ReleaseReadinessForPublish {
  can_publish: boolean
  blocking_conditions: Array<{
    code: string
    message: string
    source: 'approval' | 'requirement' | 'review' | 'evidence'
  }>
  approval_evidence: Record<string, unknown> | null
  requirement_evidence: Record<string, unknown> | null
  review_evidence: { completed_review_count: number } | null
}

export function useReleaseReadinessForPublish(
  assetId: string | undefined,
  versionId: string | undefined,
  releaseType: ReleaseType | null,
) {
  return useQuery({
    queryKey:
      assetId && versionId
        ? qk.releaseReadinessForPublish(assetId, versionId, releaseType)
        : ['release', 'readiness-for-publish', 'none'],
    enabled: Boolean(assetId && versionId),
    queryFn: async (): Promise<ReleaseReadinessForPublish | null> => {
      const { data, error } = await supabase.rpc(
        'get_release_readiness_for_publish',
        {
          p_design_asset_id: assetId as string,
          p_version_id: versionId as string,
          p_release_type: releaseType,
        },
      )
      if (error) throw error
      return (data as ReleaseReadinessForPublish | null) ?? null
    },
  })
}
