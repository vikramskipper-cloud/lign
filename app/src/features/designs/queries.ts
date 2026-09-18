import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk, type AssetFilters, type AssetNeighborScope } from '@/lib/queryKeys'

export type AssetStatus = 'draft' | 'active' | 'deprecated' | 'archived'

export interface AssetRow {
  id: string
  workspace_id: string
  project_id: string
  collection_id: string | null
  discipline_id: string | null
  name: string
  description: string | null
  code: string | null
  current_version_id: string | null
  status: AssetStatus
  archived_at: string | null
  created_at: string
  updated_at: string
}

const COLS =
  'id, workspace_id, project_id, collection_id, discipline_id, name, description, code, current_version_id, status, archived_at, created_at, updated_at'

function applyFilters<T extends { eq: any; is: any; ilike: any }>(
  qb: T,
  filters: AssetFilters,
): T {
  let q: any = qb
  if (filters.collection === 'unfiled') q = q.is('collection_id', null)
  else if (filters.collection) q = q.eq('collection_id', filters.collection)
  if (filters.discipline) q = q.eq('discipline_id', filters.discipline)
  if (filters.search.trim()) q = q.ilike('name', `%${filters.search.trim()}%`)
  return q
}

export function useAssets(projId: string | undefined, filters: AssetFilters) {
  return useQuery({
    queryKey: projId
      ? qk.assets(projId, filters)
      : ['project', 'none', 'assets', filters],
    enabled: Boolean(projId),
    queryFn: async (): Promise<AssetRow[]> => {
      let q = supabase
        .from('design_assets')
        .select(COLS)
        .eq('project_id', projId as string)
        .neq('status', 'archived')
      q = applyFilters(q, filters)
      const { data, error } = await q.order('updated_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as AssetRow[]
    },
  })
}

export function useAsset(assetId: string | undefined) {
  return useQuery({
    queryKey: assetId ? qk.asset(assetId) : ['asset', 'none'],
    enabled: Boolean(assetId),
    queryFn: async (): Promise<AssetRow | null> => {
      const { data, error } = await supabase
        .from('design_assets')
        .select(COLS)
        .eq('id', assetId as string)
        .maybeSingle()
      if (error) throw error
      return (data as AssetRow | null) ?? null
    },
  })
}

export interface AssetNeighborRow {
  id: string
  name: string
  updated_at: string
}

/**
 * Ordered list of assets in the same project (respecting collection/discipline
 * scope), used by the Design Workspace prev/next controls. Small SELECT kept
 * separate from the full grid query so opening the workspace doesn't refetch
 * a whole grid page.
 */
export function useAssetNeighbors(
  projId: string | undefined,
  assetId: string | undefined,
  scope: AssetNeighborScope,
) {
  return useQuery({
    queryKey: assetId
      ? qk.assetNeighbors(assetId, scope)
      : ['asset', 'none', 'neighbors', scope],
    enabled: Boolean(assetId && projId),
    queryFn: async (): Promise<AssetNeighborRow[]> => {
      let q = supabase
        .from('design_assets')
        .select('id, name, updated_at')
        .eq('project_id', projId as string)
        .neq('status', 'archived')
      if (scope.collection === 'unfiled') q = q.is('collection_id', null)
      else if (scope.collection) q = q.eq('collection_id', scope.collection)
      if (scope.discipline) q = q.eq('discipline_id', scope.discipline)
      const { data, error } = await q.order('updated_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as AssetNeighborRow[]
    },
  })
}
