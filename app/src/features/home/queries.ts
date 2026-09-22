import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'

/**
 * Home data layer.
 *
 * Two rules shape everything here:
 *
 * 1. Participations are resolved ONCE (useMyParticipations) and every section
 *    derives from that. A user's role is per project, so each row carries the
 *    capacity that applies to that item — Home is one feed, not a role mode.
 *
 * 2. A row only appears under "Needs you" if the user can actually act on it.
 *    That is decided by participation role, which is what lign_project_role()
 *    reads. A workspace admin who is not a participant holds the *.view keys
 *    and none of the work keys, so they must see nothing actionable here.
 *    Home never reimplements permissions; RLS still filters every read.
 *
 * Note: neither approval_requests nor reviews has a direct FK to projects —
 * they reach it only through the composite design_asset_fk. So project names
 * come from the participation map rather than an embed. Do not "fix" this by
 * adding `project:projects!..._project_fk`; that constraint does not exist and
 * PostgREST will reject the whole select with PGRST200.
 *
 * Approvals target VERSIONS, not releases (confirmed against the schema:
 * approval_requests.version_id is NOT NULL and nothing references a release).
 * A release is the published end-state; approvals happen per version on the
 * way there.
 */

export type ProjectRole = 'lead' | 'contributor' | 'reviewer' | 'approver' | 'observer'
export type Capacity = 'internal' | 'external'

export interface MyParticipation {
  participantId: string
  projectId: string
  projectName: string
  workspaceId: string
  role: ProjectRole
  capacity: Capacity
  /** workspace_members.id or stakeholders.id — what the approval/review slots key on. */
  sourceId: string
}

const ROLE_RANK: Record<ProjectRole, number> = {
  lead: 1, contributor: 2, approver: 3, reviewer: 4, observer: 5,
}

/**
 * Every project this user participates in, with the capacity they hold.
 * RLS on project_participants exposes all participants of visible projects, so
 * this MUST filter to rows that belong to the caller.
 */
export function useMyParticipations(workspaceId: string | undefined) {
  const { session } = useSession()
  const uid = session?.user?.id

  return useQuery({
    queryKey: ['home', 'participations', workspaceId ?? '', uid ?? ''],
    enabled: Boolean(workspaceId && uid),
    staleTime: 60_000,
    queryFn: async (): Promise<MyParticipation[]> => {
      const { data, error } = await supabase
        .from('project_participants')
        .select(
          `id, role, project_id, workspace_id,
           project:projects!project_participants_project_fk(id, name),
           workspace_member:workspace_members!project_participants_workspace_member_fk(id, user_id),
           stakeholder:stakeholders!project_participants_stakeholder_fk(id, user_id)`,
        )
        .eq('workspace_id', workspaceId as string)
        .eq('status', 'active')
      if (error) throw error

      type Raw = {
        id: string; role: ProjectRole; project_id: string; workspace_id: string
        project: { id: string; name: string } | null
        workspace_member: { id: string; user_id: string } | null
        stakeholder: { id: string; user_id: string | null } | null
      }

      return ((data ?? []) as unknown as Raw[])
        .filter((r) => r.workspace_member?.user_id === uid || r.stakeholder?.user_id === uid)
        .map((r) => ({
          participantId: r.id,
          projectId: r.project_id,
          projectName: r.project?.name ?? 'Untitled project',
          workspaceId: r.workspace_id,
          role: r.role,
          capacity: (r.workspace_member ? 'internal' : 'external') as Capacity,
          sourceId: (r.workspace_member?.id ?? r.stakeholder?.id) as string,
        }))
        .sort((a, b) => ROLE_RANK[a.role] - ROLE_RANK[b.role] || a.projectName.localeCompare(b.projectName))
    },
  })
}

/* ---------------------------------------------------------------------------
 * 1a. Approvals awaiting my response
 * ------------------------------------------------------------------------- */

export interface ApprovalItem {
  kind: 'approval'
  slotId: string
  requestId: string
  code: string
  title: string
  projectId: string
  projectName: string
  capacity: Capacity
  assetName: string | null
  sentByName: string | null
  dueAt: string | null
  createdAt: string
}

export function useApprovalsForMe(workspaceId: string | undefined, parts: MyParticipation[] | undefined) {
  const enabled = Boolean(workspaceId && parts)
  // Only projects where I am actually an approver. This is the capability gate
  // for this row type: approval.respond resolves through lign_project_role,
  // which reads participation.
  const approverIn = (parts ?? []).filter((p) => p.role === 'approver')
  const sourceIds = approverIn.map((p) => p.sourceId)

  return useQuery({
    queryKey: ['home', 'approvals', workspaceId ?? '', sourceIds.join(',')],
    enabled: enabled && sourceIds.length > 0,
    queryFn: async (): Promise<ApprovalItem[]> => {
      // One query: my unanswered approver slots, with the request and project
      // joined. No per-row follow-ups.
      const { data, error } = await supabase
        .from('approval_request_approvers')
        .select(
          `id, workspace_member_id, stakeholder_id, removed_at,
           request:approval_requests!approval_request_approvers_request_fk(
             id, title, status, due_at, created_at, project_id, version_id,
             created_by:profiles!approval_requests_created_by_profile_id_fkey(display_name),
             asset:design_assets!approval_requests_design_asset_fk(name)
           ),
           responses:approval_responses!approval_responses_slot_request_fk(id)`,
        )
        .eq('workspace_id', workspaceId as string)
        .is('removed_at', null)
        .in('workspace_member_id', sourceIds)
      if (error) throw error

      type Raw = {
        id: string
        workspace_member_id: string | null
        stakeholder_id: string | null
        request: {
          id: string; title: string | null; status: string; due_at: string | null
          created_at: string; project_id: string; version_id: string
          created_by: { display_name: string } | null
          asset: { name: string } | null
        } | null
        responses: { id: string }[] | null
      }

      const byProject = new Map(approverIn.map((p) => [p.projectId, p]))

      return ((data ?? []) as unknown as Raw[])
        .filter((r) => {
          const req = r.request
          if (!req) return false
          if (!['pending', 'in_progress'].includes(req.status)) return false
          if ((r.responses?.length ?? 0) > 0) return false // already answered
          return byProject.has(req.project_id)
        })
        .map((r) => {
          const req = r.request!
          const part = byProject.get(req.project_id)!
          return {
            kind: 'approval' as const,
            slotId: r.id,
            requestId: req.id,
            code: shortCode('APR', req.id),
            title: req.title || req.asset?.name || 'Approval request',
            projectId: req.project_id,
            projectName: part.projectName,
            capacity: part.capacity,
            assetName: req.asset?.name ?? null,
            sentByName: req.created_by?.display_name ?? null,
            dueAt: req.due_at,
            createdAt: req.created_at,
          }
        })
        .sort(byDueThenAge)
    },
  })
}

/* ---------------------------------------------------------------------------
 * 1b. Reviews assigned to me
 * ------------------------------------------------------------------------- */

export interface ReviewItem {
  kind: 'review'
  participantId: string
  reviewId: string
  code: string
  title: string
  projectId: string
  projectName: string
  capacity: Capacity
  openedAt: string
}

export function useReviewsForMe(workspaceId: string | undefined, parts: MyParticipation[] | undefined) {
  const reviewerIn = (parts ?? []).filter((p) => p.role === 'reviewer' || p.role === 'approver' || p.role === 'lead' || p.role === 'contributor')
  const sourceIds = reviewerIn.map((p) => p.sourceId)

  return useQuery({
    queryKey: ['home', 'reviews', workspaceId ?? '', sourceIds.join(',')],
    enabled: Boolean(workspaceId && parts) && sourceIds.length > 0,
    queryFn: async (): Promise<ReviewItem[]> => {
      const { data, error } = await supabase
        .from('review_participants')
        .select(
          `id, responded_at, status, removed_at, workspace_member_id,
           review:reviews!review_participants_review_fk(
             id, title, status, created_at, project_id,
             asset:design_assets!reviews_design_asset_fk(name)
           )`,
        )
        .eq('workspace_id', workspaceId as string)
        .is('removed_at', null)
        .is('responded_at', null)
        .in('workspace_member_id', sourceIds)
      if (error) throw error

      type Raw = {
        id: string; responded_at: string | null; status: string
        review: {
          id: string; title: string | null; status: string; created_at: string; project_id: string
          asset: { name: string } | null
        } | null
      }
      const byProject = new Map(reviewerIn.map((p) => [p.projectId, p]))

      return ((data ?? []) as unknown as Raw[])
        .filter((r) => r.review && ['open', 'in_progress'].includes(r.review.status) && byProject.has(r.review.project_id))
        .map((r) => {
          const rev = r.review!
          const part = byProject.get(rev.project_id)!
          return {
            kind: 'review' as const,
            participantId: r.id,
            reviewId: rev.id,
            code: shortCode('REV', rev.id),
            title: rev.title || rev.asset?.name || 'Review',
            projectId: rev.project_id,
            projectName: part.projectName,
            capacity: part.capacity,
            openedAt: rev.created_at,
          }
        })
        .sort((a, b) => a.openedAt.localeCompare(b.openedAt)) // oldest first
    },
  })
}

/* ---------------------------------------------------------------------------
 * 3. Your projects  —  participations + per-project counts
 * ------------------------------------------------------------------------- */

export interface ProjectCard {
  projectId: string
  projectName: string
  role: ProjectRole
  capacity: Capacity
  approvalsForMe: number
  reviewsForMe: number
}

export function buildProjectCards(
  parts: MyParticipation[],
  approvals: ApprovalItem[],
  reviews: ReviewItem[],
): ProjectCard[] {
  const cards = parts.map((p) => ({
    projectId: p.projectId,
    projectName: p.projectName,
    role: p.role,
    capacity: p.capacity,
    approvalsForMe: approvals.filter((a) => a.projectId === p.projectId).length,
    reviewsForMe: reviews.filter((r) => r.projectId === p.projectId).length,
  }))
  // Projects with something needing me first, then alphabetical. (Last-activity
  // ordering would need an activity_events aggregate per project; noted as a
  // follow-up rather than an N+1 here.)
  return cards.sort((a, b) => {
    const an = a.approvalsForMe + a.reviewsForMe
    const bn = b.approvalsForMe + b.reviewsForMe
    return bn - an || a.projectName.localeCompare(b.projectName)
  })
}

/* ---------------------------------------------------------------------------
 * 4. Recent activity
 * ------------------------------------------------------------------------- */

export interface ActivityItem {
  id: string
  eventType: string
  actorName: string | null
  subjectLabel: string | null
  occurredAt: string
  projectId: string | null
}

export function useRecentActivity(workspaceId: string | undefined, limit: number) {
  return useQuery({
    queryKey: ['home', 'activity', workspaceId ?? '', limit],
    enabled: Boolean(workspaceId),
    queryFn: async (): Promise<ActivityItem[]> => {
      // activity_events RLS already restricts this to what the caller may see
      // (activity.view). No extra filtering here, or Home would disagree with
      // the audit log.
      const { data, error } = await supabase
        .from('activity_events')
        .select('id, event_type, subject_label, occurred_at, project_id, actor:profiles!activity_events_actor_profile_id_fkey(display_name)')
        .eq('workspace_id', workspaceId as string)
        .order('occurred_at', { ascending: false })
        .limit(limit)
      if (error) throw error
      type Raw = {
        id: string; event_type: string; subject_label: string | null
        occurred_at: string; project_id: string | null
        actor: { display_name: string } | null
      }
      return ((data ?? []) as unknown as Raw[]).map((r) => ({
        id: r.id,
        eventType: r.event_type,
        actorName: r.actor?.display_name ?? null,
        subjectLabel: r.subject_label,
        occurredAt: r.occurred_at,
        projectId: r.project_id,
      }))
    },
  })
}

/* ------------------------------------------------------------------------- */

/** Stable short code from a uuid, for display only. */
export function shortCode(prefix: string, id: string): string {
  return `${prefix}-${id.replace(/-/g, '').slice(0, 4).toUpperCase()}`
}

function byDueThenAge(a: { dueAt: string | null; createdAt: string }, b: { dueAt: string | null; createdAt: string }) {
  // Overdue first, then soonest due, then oldest. Undated sorts after dated.
  const now = Date.now()
  const aOver = a.dueAt ? new Date(a.dueAt).getTime() < now : false
  const bOver = b.dueAt ? new Date(b.dueAt).getTime() < now : false
  if (aOver !== bOver) return aOver ? -1 : 1
  if (a.dueAt && b.dueAt) return a.dueAt.localeCompare(b.dueAt)
  if (a.dueAt) return -1
  if (b.dueAt) return 1
  return a.createdAt.localeCompare(b.createdAt)
}

/* ---------------------------------------------------------------------------
 * 2. Waiting on others
 *
 * Re-mapped from the brief in line with the Gap-1 decision: approvals happen
 * on versions, so "releases I issued awaiting approvers" becomes "approval
 * requests I raised, or on projects I lead, with an approver who has not
 * responded". The second half — versions I uploaded with an open review — is
 * unchanged.
 *
 * This is the lead's version of "needs you": their job is unblocking.
 * ------------------------------------------------------------------------- */

export interface WaitingItem {
  id: string
  code: string
  title: string
  projectName: string
  blockerName: string
  blockerCapacity: Capacity
  blockerRole: string
  othersCount: number
  pendingSince: string
}

export function useWaitingOnOthers(
  workspaceId: string | undefined,
  parts: MyParticipation[] | undefined,
  myProfileId: string | undefined,
) {
  const leadIn = new Set((parts ?? []).filter((p) => p.role === 'lead').map((p) => p.projectId))
  const nameByProject = new Map((parts ?? []).map((p) => [p.projectId, p.projectName]))

  return useQuery({
    queryKey: ['home', 'waiting', workspaceId ?? '', myProfileId ?? ''],
    enabled: Boolean(workspaceId && parts && myProfileId),
    queryFn: async (): Promise<WaitingItem[]> => {
      const { data, error } = await supabase
        .from('approval_requests')
        .select(
          `id, title, status, created_at, sent_at, project_id, created_by_profile_id,
           asset:design_assets!approval_requests_design_asset_fk(name),
           approvers:approval_request_approvers!approval_request_approvers_request_fk(
             id, removed_at,
             member:workspace_members!approval_request_approvers_workspace_member_fk(
               id, profile:profiles!workspace_members_user_id_fkey(display_name)),
             stakeholder:stakeholders!approval_request_approvers_stakeholder_fk(id, email, display_name),
             responses:approval_responses!approval_responses_slot_request_fk(id)
           )`,
        )
        .eq('workspace_id', workspaceId as string)
        .in('status', ['pending', 'in_progress'])
      if (error) throw error

      type RawApprover = {
        id: string; removed_at: string | null
        member: { id: string; profile: { display_name: string } | null } | null
        stakeholder: { id: string; email: string; display_name: string | null } | null
        responses: { id: string }[] | null
      }
      type Raw = {
        id: string; title: string | null; status: string; created_at: string
        sent_at: string | null; project_id: string; created_by_profile_id: string | null
        asset: { name: string } | null
        approvers: RawApprover[] | null
      }

      return ((data ?? []) as unknown as Raw[])
        // Mine to unblock: I raised it, or I lead the project it belongs to.
        .filter((r) => r.created_by_profile_id === myProfileId || leadIn.has(r.project_id))
        .map((r) => {
          const outstanding = (r.approvers ?? []).filter(
            (a) => a.removed_at === null && (a.responses?.length ?? 0) === 0,
          )
          if (outstanding.length === 0) return null
          const first = outstanding[0]!
          return {
            id: r.id,
            code: shortCode('APR', r.id),
            title: r.title || r.asset?.name || 'Approval request',
            projectName: nameByProject.get(r.project_id) ?? 'Project',
            blockerName:
              first.member?.profile?.display_name ??
              first.stakeholder?.display_name ??
              first.stakeholder?.email ??
              'Someone',
            blockerCapacity: (first.member ? 'internal' : 'external') as Capacity,
            blockerRole: 'approver',
            othersCount: outstanding.length - 1,
            pendingSince: r.sent_at ?? r.created_at,
          }
        })
        .filter((r): r is WaitingItem => r !== null)
        // Longest pending first — that is the one actually holding things up.
        .sort((a, b) => a.pendingSince.localeCompare(b.pendingSince))
    },
  })
}

/** Whole days a row has been pending, for the ochre threshold. */
export function daysPending(iso: string): number {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
}
