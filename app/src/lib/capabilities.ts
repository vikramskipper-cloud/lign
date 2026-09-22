import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { CAPABILITY_KEYS, type CapabilityKey, type CapabilityMap } from '@/types/capabilities'

/**
 * APP 013 workspace-scoped keys. lign_has_capability short-circuits these
 * before validating project scope, so they are the only keys answerable with
 * p_project_id = null.
 */
export const WORKSPACE_CAPABILITY_KEYS = [
  'member.invite',
  'member.remove',
  'member.change_role',
  'stakeholder.invite',
  'stakeholder.revoke',
  'workspace.manage',
] as const satisfies readonly CapabilityKey[]

export type WorkspaceCapabilityKey = (typeof WORKSPACE_CAPABILITY_KEYS)[number]
export type WorkspaceCapabilityMap = Record<WorkspaceCapabilityKey, boolean>

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

/**
 * APP 013: the caller's workspace-scoped capabilities, for screens with no
 * project in scope (Workspace People, Workspace Settings). Passing
 * p_project_id = null is correct here and only works for these six keys.
 */
export function useWorkspaceAccess(workspaceId: string | undefined) {
  return useQuery({
    queryKey: qk.workspaceAccess(workspaceId ?? ''),
    enabled: Boolean(workspaceId),
    staleTime: 60_000,
    queryFn: async (): Promise<WorkspaceCapabilityMap> => {
      const results = await Promise.all(
        WORKSPACE_CAPABILITY_KEYS.map(async (key) => {
          const { data, error } = await supabase.rpc('lign_has_capability', {
            p_project_id: null,
            p_workspace_id: workspaceId as string,
            p_capability_key: key,
          })
          if (error) return [key, false] as const
          return [key, Boolean(data)] as const
        }),
      )
      return Object.fromEntries(results) as WorkspaceCapabilityMap
    },
  })
}
