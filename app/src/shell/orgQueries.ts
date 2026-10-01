import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useSession } from '@/auth/SessionProvider'

/**
 * Organisation layer (APP 015). The tenant above workspace.
 *
 * Org owners and admins see every workspace the org owns; an org `member` has
 * no implicit workspace access at all. Nothing here decides that — RLS and
 * lign_is_workspace_member do. These queries only read what the caller can
 * already see.
 */

export type OrgRole = 'owner' | 'admin' | 'member'

export interface MyOrganization {
  id: string
  name: string
  slug: string
  role: OrgRole
}

export function useMyOrganizations() {
  const { session } = useSession()
  const uid = session?.user?.id

  return useQuery({
    queryKey: ['organizations', uid ?? 'anon'],
    enabled: Boolean(uid),
    staleTime: 60_000,
    queryFn: async (): Promise<MyOrganization[]> => {
      // MUST be scoped to this user. organization_members RLS exposes every
      // member of an org you belong to, so an unscoped read would hand back
      // someone else's role — the same trap useAccessCheck documents for
      // workspace_members.
      const { data, error } = await supabase
        .from('organization_members')
        .select('role, organization:organizations!organization_members_organization_id_fkey(id, name, slug)')
        .eq('user_id', uid as string)
        .eq('status', 'active')
      if (error) throw error

      type Raw = {
        role: OrgRole
        organization: { id: string; name: string; slug: string } | null
      }
      return ((data ?? []) as unknown as Raw[])
        .filter((r) => r.organization)
        .map((r) => ({
          id: r.organization!.id,
          name: r.organization!.name,
          slug: r.organization!.slug,
          role: r.role,
        }))
        .sort((a, b) => a.name.localeCompare(b.name))
    },
  })
}

/** The orgs this user may create workspaces in. */
export function useAdminOrganizations() {
  const orgs = useMyOrganizations()
  return {
    ...orgs,
    data: (orgs.data ?? []).filter((o) => o.role === 'owner' || o.role === 'admin'),
  }
}

export function useCreateWorkspace() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { name: string; organizationId: string | null }): Promise<string> => {
      const { data, error } = await supabase.rpc('create_workspace', {
        p_name: input.name,
        p_slug: null,
        p_organization_id: input.organizationId,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: async () => {
      // refetchType 'all': the caller may not have the workspace list mounted,
      // and a plain invalidate leaves inactive queries merely stale — which is
      // what caused the first-run redirect bounce.
      await Promise.all([
        qc.invalidateQueries({ queryKey: qk.workspaces(), refetchType: 'all' }),
        qc.invalidateQueries({ queryKey: ['access-check'], refetchType: 'all' }),
        qc.invalidateQueries({ queryKey: ['organizations'], refetchType: 'all' }),
      ])
    },
  })
}
