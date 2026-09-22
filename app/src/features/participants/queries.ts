import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export type ParticipantKind = 'member' | 'stakeholder'

export interface Participant {
  /** The project_participants row id (stable per project participation). */
  id: string
  /** The underlying profile id (may be null for unclaimed stakeholders). */
  profileId: string | null
  displayName: string
  email: string
  avatarUrl: string | null
  kind: ParticipantKind
  role: string
}

interface RawRow {
  id: string
  role: string
  status: string
  workspace_member_id: string | null
  stakeholder_id: string | null
  workspace_member: {
    id: string
    user_id: string
    profile: { id: string; display_name: string; email: string; avatar_url: string | null } | null
  } | null
  stakeholder: {
    id: string
    display_name: string | null
    email: string
    user_id: string | null
    profile: { id: string; display_name: string; email: string; avatar_url: string | null } | null
  } | null
}

const SELECT = `
  id, role, status, workspace_member_id, stakeholder_id,
  workspace_member:workspace_members!project_participants_workspace_member_fk (
    id, user_id,
    profile:profiles!workspace_members_user_id_fkey ( id, display_name, email, avatar_url )
  ),
  stakeholder:stakeholders!project_participants_stakeholder_fk (
    id, display_name, email, user_id,
    profile:profiles!stakeholders_user_id_fkey ( id, display_name, email, avatar_url )
  )
`

/**
 * Active project participants for a project, flattened for @-mention and
 * comment-author decoration.
 *
 * DEFECT FIXED 2026-09-22 (APP 005 amendment): the two embed hints named
 * `project_participants_workspace_member_id_fkey` and
 * `project_participants_stakeholder_id_fkey`. Neither constraint exists — the
 * real names are `..._workspace_member_fk` and `..._stakeholder_fk`. PostgREST
 * rejected the whole select with PGRST200, so this hook returned an error on
 * every call and @-mentions never populated. It typechecked and built cleanly
 * the entire time, which is why APP 005 certified around it. Unclaimed stakeholders keep their invite email
 * as fallback display.
 */
export function useProjectParticipants(projectId: string | undefined) {
  return useQuery({
    queryKey: projectId
      ? qk.projectParticipants(projectId)
      : ['project', 'none', 'participants'],
    enabled: Boolean(projectId),
    queryFn: async (): Promise<Participant[]> => {
      const { data, error } = await supabase
        .from('project_participants')
        .select(SELECT)
        .eq('project_id', projectId as string)
        .eq('status', 'active')
      if (error) throw error
      const rows = (data ?? []) as unknown as RawRow[]
      return rows.map(flatten).filter((p): p is Participant => p !== null)
    },
  })
}

function flatten(r: RawRow): Participant | null {
  if (r.workspace_member) {
    const p = r.workspace_member.profile
    if (!p) return null
    return {
      id: r.id,
      profileId: p.id,
      displayName: p.display_name,
      email: p.email,
      avatarUrl: p.avatar_url,
      kind: 'member',
      role: r.role,
    }
  }
  if (r.stakeholder) {
    const p = r.stakeholder.profile
    return {
      id: r.id,
      profileId: p?.id ?? null,
      displayName: p?.display_name ?? r.stakeholder.display_name ?? r.stakeholder.email,
      email: p?.email ?? r.stakeholder.email,
      avatarUrl: p?.avatar_url ?? null,
      kind: 'stakeholder',
      role: r.role,
    }
  }
  return null
}
