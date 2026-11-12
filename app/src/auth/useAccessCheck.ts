import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'

/**
 * "Does this account have anywhere to go?"
 *
 * The brief's rule — zero workspace memberships AND zero project
 * participations — does not produce the behaviour its own acceptance checks
 * ask for. Measured against the live fixtures:
 *
 *   p_none    1 workspace membership, 0 participations   rule -> Home,
 *                                                        checklist -> No access
 *   p_admin   2 memberships, 0 participations            must reach Home
 *   p_stake   0 memberships, 1 participation             must reach Home
 *
 * A plain OR would strand p_admin, a legitimate administrator with no project
 * work of their own. What actually separates the cases is simpler, and is what
 * the user experiences rather than what the join tables say:
 *
 *     no access  =  sees no projects  AND  is not an owner/admin anywhere
 *
 * Verified under RLS against all eight accounts: only p_none matches, and
 * every other fixture reaches Home. Note the project count MUST come from an
 * RLS-filtered read — it is "what can you actually open", not a membership
 * tally, and those differ.
 */
export interface AccessState {
  hasAccess: boolean
  visibleProjects: number
  isAdminSomewhere: boolean
  /** Workspaces this user can actually open, RLS-filtered. */
  visibleWorkspaces: number
  /** Orgs where this user is owner or admin, and so may create a workspace. */
  adminOrgIds: string[]
  /** Any active org membership at all, including plain `member`. */
  orgMemberships: number
  /**
   * Whether this account is allowed to FOUND an organisation — answered by a
   * SECURITY DEFINER probe, because the facts behind it are not readable from
   * the client.
   *
   * APP 022 replaced the old question, "does this deployment hold an
   * organisation yet". That stopped being the right one when LIGN stopped
   * being single-tenant: many organisations now coexist, so their existence
   * says nothing about whether this person may add another. What permits it is
   * an APPROVED access request for this account's own email, or being LIGN
   * staff — and `access_requests` is readable only by platform admins, so the
   * client cannot work it out for itself.
   *
   * Still a courtesy either way: create_organization re-checks and is the
   * control.
   */
  mayFoundOrganization: boolean
  /**
   * Send them to /welcome.
   *
   * The honest condition is "can open no workspace AND can do something about
   * it". Two cases qualify: an APPROVED APPLICANT with no organisation yet
   * (founds both), and an org owner/admin whose org has no workspace yet
   * (creates one in it).
   *
   * An org *member* with no workspace is deliberately excluded — they cannot
   * create anything, so /welcome would be a form that always fails. So is a
   * signed-up stranger with no approved application: under APP 022 nothing
   * they type will be accepted. Both get /no-access, which is the truth —
   * someone has to add them, or approve them.
   *
   * Counting workspaces rather than memberships also keeps stakeholders out of
   * here. An external client has no workspace_members row at all — p_stake was
   * the fixture for exactly that — but RLS does show them the workspace their
   * project lives in, so they land in the app like everyone else.
   */
  needsWorkspace: boolean
}

export function useAccessCheck() {
  const { session } = useSession()
  const uid = session?.user?.id

  return useQuery({
    queryKey: ['access-check', uid ?? 'anon'],
    enabled: Boolean(uid),
    staleTime: 30_000,
    queryFn: async (): Promise<AccessState> => {
      const [projects, roles, workspaces, orgs, mayFound] = await Promise.all([
        // RLS-filtered: exactly the projects this user could open.
        supabase.from('projects').select('id').limit(1),
        // MUST be scoped to this user. workspace_members RLS exposes every
        // member of a workspace you belong to, so an unscoped read would see
        // someone else's admin row and wrongly mark a plain member as admin.
        supabase
          .from('workspace_members')
          .select('role')
          .eq('user_id', uid as string)
          .eq('status', 'active'),
        // RLS-filtered: includes workspaces reached as an org admin or as a
        // stakeholder, not just ones with a membership row.
        supabase.from('workspaces').select('id'),
        // Scoped to this user for the same reason the workspace read is:
        // organization_members RLS exposes every member of your org.
        supabase
          .from('organization_members')
          .select('organization_id, role')
          .eq('user_id', uid as string)
          .eq('status', 'active'),
        supabase.rpc('lign_may_found_organization'),
      ])

      // A failed read is not evidence of "no access". Let the user through
      // rather than locking out a valid account on a transient error.
      if (projects.error || roles.error || workspaces.error || orgs.error) {
        return {
          hasAccess: true, visibleProjects: -1, isAdminSomewhere: false,
          visibleWorkspaces: -1, adminOrgIds: [], orgMemberships: 0,
          // Fail closed on a bad probe. Guessing "yes, you may found one"
          // would send someone into a form create_organization then refuses.
          mayFoundOrganization: false,
          // Never onboard on a failed read: that would offer a workspace to
          // someone who already has one and just hit a flaky network.
          needsWorkspace: false,
        }
      }

      const visibleProjects = projects.data?.length ?? 0
      const isAdminSomewhere = (roles.data ?? []).some(
        (r) => r.role === 'owner' || r.role === 'admin',
      )
      const visibleWorkspaces = workspaces.data?.length ?? 0
      const orgRows = orgs.data ?? []
      const adminOrgIds = orgRows
        .filter((o) => o.role === 'owner' || o.role === 'admin')
        .map((o) => o.organization_id as string)

      // A failed probe is treated as "not permitted", for the same reason.
      const mayFoundOrganization = mayFound.error ? false : Boolean(mayFound.data)

      return {
        hasAccess: visibleProjects > 0 || isAdminSomewhere || visibleWorkspaces > 0,
        visibleProjects,
        isAdminSomewhere,
        visibleWorkspaces,
        adminOrgIds,
        orgMemberships: orgRows.length,
        mayFoundOrganization,
        // Two cases can act, and only these two:
        //   * an org admin whose organisation has no workspace yet;
        //   * an approved applicant who has not founded their company yet.
        // Everyone else with nothing to open is waiting on an invitation or on
        // approval, and belongs on /no-access rather than in front of a form
        // that refuses.
        needsWorkspace:
          visibleWorkspaces === 0 &&
          (adminOrgIds.length > 0 || (orgRows.length === 0 && mayFoundOrganization)),
      }
    },
  })
}
