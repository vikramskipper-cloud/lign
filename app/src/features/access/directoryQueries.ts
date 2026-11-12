import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import type { OrgRole } from '@/shell/orgQueries'
import type { WorkspaceRole, ProjectRole } from './queries'

export interface DirectoryProject {
  id: string; projectId: string; projectName: string; projectStatus: string; archived: boolean
  workspaceId: string; role: ProjectRole; source: 'internal' | 'external'; sourceId: string; status: string
}
export interface DirectoryPerson {
  id: string; userId: string | null; name: string; email: string; internal: boolean
  organizationRole: OrgRole | null; organizationStatus: string | null; inheritedAdministration: boolean
  workspaceRoles: { workspaceId: string; role: WorkspaceRole; status: string }[]
  projectRoles: DirectoryProject[]
}
export interface AccessDirectory {
  organizationId: string; organizationName: string
  workspaces: { id: string; name: string; status: string }[]
  people: DirectoryPerson[]
  pendingInvitations: { id: string; email: string; scope: 'organization' | 'workspace' | 'external'; workspaceId: string | null; role: string; expiresAt: string }[]
}
export function useAccessDirectory(orgId?: string, wsId?: string, enabled = true) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['access-directory', user?.id, orgId ?? null, wsId ?? null],
    enabled: enabled && Boolean(user && (orgId || wsId)),
    refetchInterval: 30_000,
    retry: (count, error) => (error as { code?: string }).code !== '42501' && count < 2,
    queryFn: async (): Promise<AccessDirectory> => {
      const { data, error } = await supabase.rpc('get_access_directory', { p_organization_id: orgId ?? null, p_workspace_id: wsId ?? null })
      if (error) throw error
      return data as AccessDirectory
    },
  })
}
