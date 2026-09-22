import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

/**
 * APP 013 read layer.
 *
 * All four access tables are SELECT-only by design — writes go through the
 * RPCs in ./mutations.ts. These queries read them directly, so RLS is what
 * decides visibility: a non-admin sees the roster but the mutations reject
 * them, and the UI hides the controls so they never find out the hard way.
 */

export type WorkspaceRole = 'owner' | 'admin' | 'member'
export type ProjectRole = 'lead' | 'contributor' | 'reviewer' | 'approver' | 'observer'

export const WORKSPACE_ROLES: WorkspaceRole[] = ['owner', 'admin', 'member']
export const PROJECT_ROLES: ProjectRole[] = [
  'lead',
  'contributor',
  'reviewer',
  'approver',
  'observer',
]

export interface WorkspaceMemberRow {
  id: string
  profileId: string
  displayName: string
  email: string
  avatarUrl: string | null
  role: WorkspaceRole
  status: string
  activatedAt: string | null
}

export interface StakeholderRow {
  id: string
  email: string
  displayName: string | null
  status: string
  /** Null until the invitee signs in and claims the invitation. */
  claimedProfileId: string | null
  invitedAt: string
}

export interface InvitationRow {
  id: string
  email: string
  kind: 'workspace_member' | 'stakeholder'
  role: string | null
  status: string
  expiresAt: string
  createdAt: string
  invitedByName: string | null
}

export interface ProjectParticipantRow {
  id: string
  kind: 'member' | 'stakeholder'
  /** workspace_members.id or stakeholders.id — what the RPCs take. */
  sourceId: string
  displayName: string
  email: string
  role: ProjectRole
  /** A stakeholder who has not yet claimed their invitation cannot act. */
  pending: boolean
}

export function useWorkspacePeople(wsId: string | undefined) {
  return useQuery({
    queryKey: qk.workspacePeople(wsId ?? ''),
    enabled: Boolean(wsId),
    queryFn: async () => {
      const [members, stakeholders] = await Promise.all([
        supabase
          .from('workspace_members')
          .select(
            'id, role, status, activated_at, user_id, profile:profiles!workspace_members_user_id_fkey(id, display_name, email, avatar_url)',
          )
          .eq('workspace_id', wsId as string)
          .neq('status', 'removed'),
        supabase
          .from('stakeholders')
          .select('id, email, display_name, status, user_id, invited_at')
          .eq('workspace_id', wsId as string)
          .neq('status', 'revoked'),
      ])
      if (members.error) throw members.error
      if (stakeholders.error) throw stakeholders.error

      // PostgREST types embedded relations as arrays; the runtime shape for a
      // to-one embed is a single object. Same cast the frozen
      // features/participants/queries.ts uses.
      type RawMember = {
        id: string; role: string; status: string; activated_at: string | null
        profile: { id: string; display_name: string; email: string; avatar_url: string | null } | null
      }
      const memberRows: WorkspaceMemberRow[] = ((members.data ?? []) as unknown as RawMember[])
        .map((r) => {
          const p = r.profile
          if (!p) return null
          return {
            id: r.id,
            profileId: p.id,
            displayName: p.display_name,
            email: p.email,
            avatarUrl: p.avatar_url,
            role: r.role as WorkspaceRole,
            status: r.status,
            activatedAt: r.activated_at ?? null,
          }
        })
        .filter((r): r is WorkspaceMemberRow => r !== null)
        .sort((a, b) => a.displayName.localeCompare(b.displayName))

      const stakeholderRows: StakeholderRow[] = (stakeholders.data ?? [])
        .map((r) => ({
          id: r.id as string,
          email: r.email as string,
          displayName: (r.display_name as string | null) ?? null,
          status: r.status as string,
          claimedProfileId: (r.user_id as string | null) ?? null,
          invitedAt: r.invited_at as string,
        }))
        .sort((a, b) => a.email.localeCompare(b.email))

      return { members: memberRows, stakeholders: stakeholderRows }
    },
  })
}

/** Pending invitations only — accepted and revoked ones are history, not a task list. */
export function useWorkspaceInvitations(wsId: string | undefined) {
  return useQuery({
    queryKey: qk.workspaceInvitations(wsId ?? ''),
    enabled: Boolean(wsId),
    queryFn: async (): Promise<InvitationRow[]> => {
      const { data, error } = await supabase
        .from('invitations')
        .select(
          'id, email, kind, role, status, expires_at, created_at, invited_by:profiles!invitations_invited_by_profile_id_fkey(display_name)',
        )
        .eq('workspace_id', wsId as string)
        .eq('status', 'sent')
        .order('created_at', { ascending: false })
      if (error) throw error
      type RawInv = {
        id: string; email: string; kind: InvitationRow['kind']; role: string | null
        status: string; expires_at: string; created_at: string
        invited_by: { display_name: string } | null
      }
      return ((data ?? []) as unknown as RawInv[]).map((r) => ({
        id: r.id,
        email: r.email,
        kind: r.kind,
        role: r.role ?? null,
        status: r.status,
        expiresAt: r.expires_at,
        createdAt: r.created_at,
        invitedByName: r.invited_by?.display_name ?? null,
      }))
    },
  })
}

export function useProjectAccess(projId: string | undefined) {
  return useQuery({
    queryKey: qk.projectAccess(projId ?? ''),
    enabled: Boolean(projId),
    queryFn: async (): Promise<ProjectParticipantRow[]> => {
      const { data, error } = await supabase
        .from('project_participants')
        .select(
          `id, role, status, workspace_member_id, stakeholder_id,
           workspace_member:workspace_members!project_participants_workspace_member_fk(
             id, profile:profiles!workspace_members_user_id_fkey(display_name, email)),
           stakeholder:stakeholders!project_participants_stakeholder_fk(
             id, display_name, email, user_id)`,
        )
        .eq('project_id', projId as string)
        .eq('status', 'active')
      if (error) throw error

      type Raw = {
        id: string
        role: string
        workspace_member_id: string | null
        stakeholder_id: string | null
        workspace_member: { id: string; profile: { display_name: string; email: string } | null } | null
        stakeholder: { id: string; display_name: string | null; email: string; user_id: string | null } | null
      }

      return ((data ?? []) as unknown as Raw[])
        .map((r): ProjectParticipantRow | null => {
          if (r.workspace_member?.profile) {
            return {
              id: r.id,
              kind: 'member',
              sourceId: r.workspace_member.id,
              displayName: r.workspace_member.profile.display_name,
              email: r.workspace_member.profile.email,
              role: r.role as ProjectRole,
              pending: false,
            }
          }
          if (r.stakeholder) {
            return {
              id: r.id,
              kind: 'stakeholder',
              sourceId: r.stakeholder.id,
              displayName: r.stakeholder.display_name ?? r.stakeholder.email,
              email: r.stakeholder.email,
              role: r.role as ProjectRole,
              pending: r.stakeholder.user_id === null,
            }
          }
          return null
        })
        .filter((r): r is ProjectParticipantRow => r !== null)
        .sort((a, b) => a.displayName.localeCompare(b.displayName))
    },
  })
}

/**
 * Workspace members not yet participating in this project. Drives the "add
 * someone" picker; offering people who are already on the project produces a
 * confusing duplicate error from the RPC.
 */
export function useAssignableMembers(wsId: string | undefined, projId: string | undefined) {
  return useQuery({
    queryKey: qk.assignableMembers(wsId ?? '', projId ?? ''),
    enabled: Boolean(wsId && projId),
    queryFn: async (): Promise<WorkspaceMemberRow[]> => {
      const [all, existing] = await Promise.all([
        supabase
          .from('workspace_members')
          .select(
            'id, role, status, activated_at, profile:profiles!workspace_members_user_id_fkey(id, display_name, email, avatar_url)',
          )
          .eq('workspace_id', wsId as string)
          .eq('status', 'active'),
        supabase
          .from('project_participants')
          .select('workspace_member_id')
          .eq('project_id', projId as string)
          .eq('status', 'active'),
      ])
      if (all.error) throw all.error
      if (existing.error) throw existing.error

      const taken = new Set(
        (existing.data ?? []).map((r) => r.workspace_member_id as string | null).filter(Boolean),
      )
      type RawAssignable = {
        id: string; role: string; status: string; activated_at: string | null
        profile: { id: string; display_name: string; email: string; avatar_url: string | null } | null
      }
      return ((all.data ?? []) as unknown as RawAssignable[])
        .filter((r) => !taken.has(r.id))
        .map((r) => {
          const p = r.profile
          if (!p) return null
          return {
            id: r.id,
            profileId: p.id,
            displayName: p.display_name,
            email: p.email,
            avatarUrl: p.avatar_url,
            role: r.role as WorkspaceRole,
            status: r.status,
            activatedAt: r.activated_at ?? null,
          }
        })
        .filter((r): r is WorkspaceMemberRow => r !== null)
        .sort((a, b) => a.displayName.localeCompare(b.displayName))
    },
  })
}
