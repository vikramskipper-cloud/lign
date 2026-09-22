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
  /**
   * First run: nowhere to go AND nobody to wait for, so the answer is to
   * create a workspace rather than to sit on /no-access.
   *
   * Requires BOTH counts to be zero. A stakeholder has no workspace_members
   * row at all — p_stake was the fixture for exactly this — so "no membership"
   * alone would send an external client to the first-run screen and offer them
   * a workspace of their own. Their visible projects are what place them.
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
      const [projects, roles] = await Promise.all([
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
      ])

      // A failed read is not evidence of "no access". Let the user through
      // rather than locking out a valid account on a transient error.
      if (projects.error || roles.error) {
        return {
          hasAccess: true, visibleProjects: -1, isAdminSomewhere: false,
          // Never onboard on a failed read: that would offer a workspace to
          // someone who already has one and just hit a flaky network.
          needsWorkspace: false,
        }
      }

      const visibleProjects = projects.data?.length ?? 0
      const isAdminSomewhere = (roles.data ?? []).some(
        (r) => r.role === 'owner' || r.role === 'admin',
      )
      const memberships = roles.data?.length ?? 0
      return {
        hasAccess: visibleProjects > 0 || isAdminSomewhere,
        visibleProjects,
        isAdminSomewhere,
        needsWorkspace: memberships === 0 && visibleProjects === 0,
      }
    },
  })
}
