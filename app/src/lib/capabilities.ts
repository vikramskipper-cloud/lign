import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { CAPABILITY_KEYS, type CapabilityKey, type CapabilityMap } from '@/types/capabilities'

async function fetchCapabilityMap(
  projectId: string,
  workspaceId: string,
): Promise<CapabilityMap> {
  // Backend has no bulk RPC yet (flagged in APP 002 §18). Fetch concurrently
  // via lign_has_capability; the map is cached per (proj, ws) for 60s.
  const results = await Promise.all(
    CAPABILITY_KEYS.map(async (key) => {
      const { data, error } = await supabase.rpc('lign_has_capability', {
        p_project_id: projectId,
        p_workspace_id: workspaceId,
        p_capability_key: key,
      })
      if (error) return [key, false] as const
      return [key, Boolean(data)] as const
    }),
  )
  return Object.fromEntries(results) as CapabilityMap
}

/**
 * Fetch the caller's full capability map for a project.
 * SessionProvider is responsible for invalidating this on 401/403 mutations.
 */
export function useProjectCapabilities(projectId: string, workspaceId: string) {
  return useQuery({
    queryKey: qk.projectCapabilities(projectId, workspaceId),
    queryFn: () => fetchCapabilityMap(projectId, workspaceId),
    staleTime: 60_000,
    enabled: Boolean(projectId && workspaceId),
  })
}

/** Convenience: single-capability lookup that derives from the same cache. */
export function useCapability(
  projectId: string | undefined,
  workspaceId: string | undefined,
  key: CapabilityKey,
): boolean {
  const { data } = useProjectCapabilities(projectId ?? '', workspaceId ?? '')
  if (!projectId || !workspaceId) return false
  return Boolean(data?.[key])
}
