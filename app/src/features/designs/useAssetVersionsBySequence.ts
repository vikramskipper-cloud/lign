import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

/**
 * Fetches sequence numbers for a set of asset_version ids in one round trip.
 * Used by the asset grid so each tile can show its "vN" chip without N queries.
 */
export function useAssetVersionsBySequence(versionIds: string[]): Map<string, number> {
  const key = ['asset-versions-by-id', [...versionIds].sort()] as const
  const { data } = useQuery({
    queryKey: key,
    enabled: versionIds.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('asset_versions')
        .select('id, sequence')
        .in('id', versionIds)
      if (error) throw error
      return data ?? []
    },
  })
  const map = new Map<string, number>()
  for (const row of data ?? []) map.set(row.id, row.sequence)
  return map
}
