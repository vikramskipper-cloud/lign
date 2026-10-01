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

/* --------------------------------------------------------------------------
 * Organisation membership.
 *
 * Two ways in, because they answer different questions. add_org_member takes a
 * profile id and is for someone who already has an account you can see.
 * invite_org_member takes an email and is for someone who does not — it stores
 * a row in organization_invitations and returns a one-time token.
 *
 * APP 016e gave organisation invitations their own table rather than loosening
 * invitations.workspace_id, which is NOT NULL and frozen.
 * ------------------------------------------------------------------------ */

export interface OrgMember {
  memberId: string
  userId: string
  name: string
  email: string
  role: OrgRole
  status: string
  activatedAt: string | null
}

export function useOrgMembers(organizationId: string | undefined) {
  return useQuery({
    queryKey: ['org-members', organizationId ?? ''],
    enabled: Boolean(organizationId),
    staleTime: 30_000,
    queryFn: async (): Promise<OrgMember[]> => {
      const { data, error } = await supabase
        .from('organization_members')
        .select(
          'id, user_id, role, status, activated_at, ' +
          'profile:profiles!organization_members_user_id_fkey(display_name, email)',
        )
        .eq('organization_id', organizationId as string)
        .neq('status', 'removed')
      if (error) throw error

      type Raw = {
        id: string
        user_id: string
        role: OrgRole
        status: string
        activated_at: string | null
        profile: { display_name: string | null; email: string } | null
      }
      const RANK: Record<string, number> = { owner: 0, admin: 1, member: 2 }
      return ((data ?? []) as unknown as Raw[])
        .map((m) => ({
          memberId: m.id,
          userId: m.user_id,
          name: m.profile?.display_name ?? m.profile?.email ?? 'Unknown',
          email: (m.profile?.email ?? '').toLowerCase(),
          role: m.role,
          status: m.status,
          activatedAt: m.activated_at,
        }))
        .sort((a, b) => (RANK[a.role] ?? 9) - (RANK[b.role] ?? 9) || a.name.localeCompare(b.name))
    },
  })
}

/** Profiles not yet in this organisation, for the add control. */
export function useAddableProfiles(organizationId: string | undefined) {
  const members = useOrgMembers(organizationId)
  return useQuery({
    queryKey: ['org-addable', organizationId ?? '', (members.data ?? []).length],
    enabled: Boolean(organizationId) && members.isSuccess,
    staleTime: 30_000,
    queryFn: async () => {
      // RLS on profiles only exposes people you already share a workspace or
      // project with, so this is never a directory of every account.
      const { data, error } = await supabase
        .from('profiles')
        .select('id, display_name, email')
        .eq('status', 'active')
      if (error) throw error
      const taken = new Set((members.data ?? []).map((m) => m.userId))
      return ((data ?? []) as { id: string; display_name: string | null; email: string }[])
        .filter((p) => !taken.has(p.id))
        .map((p) => ({ id: p.id, name: p.display_name ?? p.email, email: p.email.toLowerCase() }))
        .sort((a, b) => a.name.localeCompare(b.name))
    },
  })
}

function orgInvalidate(qc: ReturnType<typeof useQueryClient>, organizationId: string) {
  return Promise.all([
    qc.invalidateQueries({ queryKey: ['org-members', organizationId], refetchType: 'all' }),
    qc.invalidateQueries({ queryKey: ['org-addable'], refetchType: 'all' }),
    qc.invalidateQueries({ queryKey: ['organizations'], refetchType: 'all' }),
    // Role changes move workspaces in and out of view, so the things that
    // decide where a person can go have to be refetched too.
    qc.invalidateQueries({ queryKey: qk.workspaces(), refetchType: 'all' }),
    qc.invalidateQueries({ queryKey: ['access-check'], refetchType: 'all' }),
  ])
}

export function useAddOrgMember(organizationId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { userId: string; role: OrgRole }) => {
      const { error } = await supabase.rpc('add_org_member', {
        p_organization_id: organizationId,
        p_user_id: input.userId,
        p_role: input.role,
      })
      if (error) throw error
    },
    onSuccess: () => orgInvalidate(qc, organizationId),
  })
}

export function useChangeOrgMemberRole(organizationId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { memberId: string; role: OrgRole }) => {
      const { error } = await supabase.rpc('change_org_member_role', {
        p_organization_member_id: input.memberId,
        p_role: input.role,
      })
      if (error) throw error
    },
    onSuccess: () => orgInvalidate(qc, organizationId),
  })
}

export function useRemoveOrgMember(organizationId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (memberId: string) => {
      const { error } = await supabase.rpc('remove_org_member', {
        p_organization_member_id: memberId,
      })
      if (error) throw error
    },
    onSuccess: () => orgInvalidate(qc, organizationId),
  })
}

/* ---------------------------------------------------- org invitations ----- */

export interface OrgInvitation {
  id: string
  email: string
  role: OrgRole
  status: string
  expiresAt: string
  createdAt: string
}

export function useOrgInvitations(organizationId: string | undefined) {
  return useQuery({
    queryKey: ['org-invitations', organizationId ?? ''],
    enabled: Boolean(organizationId),
    staleTime: 30_000,
    queryFn: async (): Promise<OrgInvitation[]> => {
      const { data, error } = await supabase
        .from('organization_invitations')
        .select('id, email, role, status, expires_at, created_at')
        .eq('organization_id', organizationId as string)
        .eq('status', 'sent')
        .order('created_at', { ascending: false })
      if (error) throw error
      return ((data ?? []) as {
        id: string; email: string; role: OrgRole
        status: string; expires_at: string; created_at: string
      }[]).map((r) => ({
        id: r.id,
        email: r.email.toLowerCase(),
        role: r.role,
        status: r.status,
        expiresAt: r.expires_at,
        createdAt: r.created_at,
      }))
    },
  })
}

export interface OrgInviteResult {
  invitationId: string
  /** Shown ONCE. Only its sha256 reaches the database. */
  token: string
  expiresAt: string
}

/** The link an org invitee opens. Copy-link delivery — no email is sent. */
export function orgInviteUrl(token: string): string {
  return `${window.location.origin}/org-invite/${token}`
}

/** Raised when the address is already a member, or already has a live invite. */
export class OrgInviteConflict extends Error {
  constructor(public readonly kind: 'member' | 'pending', public readonly email: string | null) {
    super(kind)
    this.name = 'OrgInviteConflict'
  }
}

export function useInviteOrgMember(organizationId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { email: string; role: OrgRole }): Promise<OrgInviteResult> => {
      const { data, error } = await supabase.rpc('invite_org_member', {
        p_organization_id: organizationId,
        p_email: input.email.trim(),
        p_role: input.role,
        p_expires_in_days: 14,
      })
      if (error) {
        if (error.code === '23505' && error.message?.includes('ORG_MEMBER_EXISTS')) {
          throw new OrgInviteConflict('member', error.details ?? null)
        }
        if (error.code === '23505' && error.message?.includes('ORG_INVITE_PENDING')) {
          throw new OrgInviteConflict('pending', error.details ?? null)
        }
        throw error
      }
      const row = Array.isArray(data) ? data[0] : data
      return {
        invitationId: row.out_invitation_id as string,
        token: row.out_token as string,
        expiresAt: row.out_expires_at as string,
      }
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['org-invitations', organizationId], refetchType: 'all' }),
  })
}

export function useRevokeOrgInvitation(organizationId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (invitationId: string) => {
      const { error } = await supabase.rpc('revoke_org_invitation', {
        p_invitation_id: invitationId,
      })
      if (error) throw error
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ['org-invitations', organizationId], refetchType: 'all' }),
  })
}

export function useAcceptOrgInvitation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (token: string): Promise<string> => {
      const { data, error } = await supabase.rpc('accept_org_invitation', { p_token: token })
      if (error) throw error
      return data as string
    },
    onSuccess: async () => {
      // Accepting changes which workspaces exist for this account, so the
      // things that decide where they can go must be refetched before any
      // redirect — not merely marked stale.
      await Promise.all([
        qc.invalidateQueries({ queryKey: ['organizations'], refetchType: 'all' }),
        qc.invalidateQueries({ queryKey: qk.workspaces(), refetchType: 'all' }),
        qc.invalidateQueries({ queryKey: ['access-check'], refetchType: 'all' }),
      ])
    },
  })
}
