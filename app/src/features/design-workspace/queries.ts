import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export type VersionStatus = 'draft' | 'published' | 'superseded' | 'deprecated'

export interface AssetVersionRow {
  id: string
  workspace_id: string
  project_id: string
  design_asset_id: string
  sequence: number
  label: string | null
  notes: string | null
  status: VersionStatus
  published_at: string | null
  published_by_profile_id: string | null
  deprecated_at: string | null
  deprecation_note: string | null
  created_at: string
  updated_at: string
}

const COLS =
  'id, workspace_id, project_id, design_asset_id, sequence, label, notes, status, published_at, published_by_profile_id, deprecated_at, deprecation_note, created_at, updated_at'

export function useAssetVersions(assetId: string | undefined) {
  return useQuery({
    queryKey: assetId ? qk.assetVersions(assetId) : ['asset', 'none', 'versions'],
    enabled: Boolean(assetId),
    queryFn: async (): Promise<AssetVersionRow[]> => {
      const { data, error } = await supabase
        .from('asset_versions')
        .select(COLS)
        .eq('design_asset_id', assetId as string)
        .order('sequence', { ascending: false })
      if (error) throw error
      return (data ?? []) as AssetVersionRow[]
    },
  })
}

export function useAssetVersion(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.assetVersion(id) : ['asset-version', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<AssetVersionRow | null> => {
      const { data, error } = await supabase
        .from('asset_versions')
        .select(COLS)
        .eq('id', id as string)
        .maybeSingle()
      if (error) throw error
      return (data as AssetVersionRow | null) ?? null
    },
  })
}
