import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import { qk } from '@/lib/queryKeys'

export interface OverviewLead { name: string; userId: string | null; role?: string }
export interface OverviewProject {
  id: string; name: string; status: string; code: string | null
  updatedAt: string; latestActivityAt: string
  leads: OverviewLead[]; pendingReviews: number; pendingApprovals: number
}
export interface OverviewWorkspace {
  id: string; name: string; status: string; teamCount: number
  leads: OverviewLead[]; projects: OverviewProject[]
}
export interface StudioOverview {
  organizationId: string; organizationName: string
  workspaces: OverviewWorkspace[]
  activity: { id: string; occurredAt: string; eventType: string; subject: string | null; actor: string; workspaceId: string; workspaceName: string; projectId: string | null }[]
}
export function useStudioOverview(orgId?: string, wsId?: string) {
  const { user } = useSession()
  return useQuery({
    queryKey: qk.studioOverview(orgId, wsId, user?.id),
    enabled: Boolean(user && (orgId || wsId)),
    refetchInterval: 30_000,
    retry: (count, error) => (error as { code?: string }).code !== '42501' && count < 2,
    queryFn: async (): Promise<StudioOverview> => {
      const { data, error } = await supabase.rpc('get_studio_overview', {
        p_organization_id: orgId ?? null, p_workspace_id: wsId ?? null,
      })
      if (error) throw error
      return data as StudioOverview
    },
  })
}
