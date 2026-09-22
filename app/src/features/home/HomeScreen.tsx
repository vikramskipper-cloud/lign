import * as React from 'react'
import { Link, Navigate } from 'react-router'
import { Check } from 'lucide-react'
import { useSession } from '@/auth/SessionProvider'
import { useWorkspaceAccess } from '@/lib/capabilities'
import { useAccessCheck } from '@/auth/useAccessCheck'
import { useActiveWorkspaceId } from '@/shell/useActiveWorkspace'
import { useWorkspace } from '@/shell/queries'
import { LoadingPage } from '@/ui/loading-page'
import { Skeleton } from '@/ui/skeleton'
import { relative } from '@/lib/formatDate'
import { RequestChangesDialog } from './RequestChangesDialog'
import { useRespondToApproval } from './mutations'
import {
  ACTIVITY_CAP, NEEDS_YOU_CAP, PROJECTS_CAP, STALE_AFTER_DAYS, WAITING_CAP,
} from './copy'
import {
  buildProjectCards, daysPending, useApprovalsForMe, useMyParticipations,
  useRecentActivity, useReviewsForMe, useWaitingOnOthers,
  type ApprovalItem, type Capacity,
} from './queries'

/* --- small presentational pieces ----------------------------------------- */

const CHIP: Record<string, { fg: string; bg: string }> = {
  approver: { fg: '#8A3A13', bg: '#FAEDE5' },
  external: { fg: '#7A5A18', bg: '#F7EFDC' },
  default: { fg: '#5E554D', bg: '#F1ECE5' },
}

function Chip({ label, tone = 'default' }: { label: string; tone?: keyof typeof CHIP | string }) {
  const c = CHIP[tone] ?? CHIP.default
  return (
    <span
      className="auth-mono"
      style={{
        fontSize: 10, letterSpacing: '0.08em', padding: '2px 6px', borderRadius: 4,
        color: c.fg, background: c.bg, whiteSpace: 'nowrap',
      }}
    >
      {label.toUpperCase()}
    </span>
  )
}

/** Capacity is never dropped to save space — it is the audit trail's backbone. */
function CapacityChip({ capacity }: { capacity: Capacity }) {
  return capacity === 'external' ? <Chip label="external" tone="external" /> : null
}

function Section({
  title, children, action,
}: { title: string; children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <section style={{ marginBottom: 24 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 8 }}>
        <h2 style={{ margin: 0, fontSize: 13, fontWeight: 600, color: 'var(--ink)' }}>{title}</h2>
        {action}
      </div>
      {children}
    </section>
  )
}

function SectionError({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="home-card" role="alert" style={{ padding: 14, fontSize: 13.5, color: 'var(--muted)' }}>
      Couldn&apos;t load this section.{' '}
      <button onClick={onRetry} style={{ background: 'none', border: 'none', padding: 0, color: 'var(--link)', cursor: 'pointer', font: 'inherit', textDecoration: 'underline' }}>
        Retry
      </button>
    </div>
  )
}

function Rows({ children }: { children: React.ReactNode }) {
  return <div className="home-card">{children}</div>
}

const btn = (kind: 'primary' | 'secondary'): React.CSSProperties => ({
  height: 32, padding: '0 12px', borderRadius: 7, fontSize: 12.5, cursor: 'pointer',
  fontFamily: 'var(--font-ui)', whiteSpace: 'nowrap',
  background: kind === 'primary' ? 'var(--accent)' : 'var(--surface)',
  color: kind === 'primary' ? '#fff' : 'var(--text)',
  border: kind === 'primary' ? 'none' : '1px solid var(--border)',
})

/* --- screen --------------------------------------------------------------- */

export function HomeScreen() {
  const { session, user, isLoading } = useSession()
  const accessCheck = useAccessCheck()
  // Same resolution AppShell uses, so the rail and this page cannot disagree
  // about which workspace is in scope.
  const { workspaceId, isLoading: wsLoading } = useActiveWorkspaceId()
  const workspace = useWorkspace(workspaceId)

  const [dialogFor, setDialogFor] = React.useState<ApprovalItem | null>(null)
  const [optimistic, setOptimistic] = React.useState<Set<string>>(new Set())

  const wsAccess = useWorkspaceAccess(workspaceId)
  const parts = useMyParticipations(workspaceId)
  const approvals = useApprovalsForMe(workspaceId, parts.data)
  const reviews = useReviewsForMe(workspaceId, parts.data)
  const waiting = useWaitingOnOthers(workspaceId, parts.data, user?.id)
  const activity = useRecentActivity(workspaceId, ACTIVITY_CAP)
  const respond = useRespondToApproval()

  if (isLoading) return <LoadingPage />
  if (!session) return <Navigate to="/sign-in" replace />
  // Guard: an account with nothing to open never belongs on Home.
  if (accessCheck.data && !accessCheck.data.hasAccess) return <Navigate to="/no-access" replace />
  if (wsLoading) return <LoadingPage />
  if (!workspaceId) return <Navigate to="/no-access" replace />

  const participations = parts.data ?? []
  const isParticipant = participations.length > 0
  const approvalRows = (approvals.data ?? []).filter((a) => !optimistic.has(a.slotId))
  const reviewRows = reviews.data ?? []
  const needsYou = [...approvalRows, ...reviewRows]
  const needsCount = needsYou.length
  const projectsWithItems = new Set(needsYou.map((i) => i.projectId)).size
  const cards = buildProjectCards(participations, approvalRows, reviewRows)
  const canCreateProject = Boolean(wsAccess.data?.['workspace.manage'])

  const firstName = (user?.email ?? '').split('@')[0]?.split(/[.\-_]/)[0] ?? 'there'
  const hour = new Date().getHours()
  const partOfDay = hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening'

  const projectsHref = `/workspace/${workspaceId}/projects`

  const doRespond = (item: ApprovalItem, decision: 'approved' | 'changes_requested', comment?: string) => {
    setOptimistic((s) => new Set(s).add(item.slotId))
    respond.mutate(
      { slotId: item.slotId, decision, comment },
      {
        onError: () =>
          setOptimistic((s) => { const n = new Set(s); n.delete(item.slotId); return n }),
      },
    )
  }

  return (
    <>
      <div className="home-grid">
        {/* header ------------------------------------------------------- */}
        <div style={{ gridColumn: '1 / -1', display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 16, marginBottom: 4 }}>
          <div>
            <h1 className="auth-display" style={{ margin: 0, fontSize: 'clamp(26px, 4vw, 34px)', lineHeight: 1.12 }}>
              Good {partOfDay}, {firstName}
            </h1>
            <p style={{ margin: '6px 0 0', fontSize: 14, color: 'var(--muted)' }}>
              {needsCount > 0
                ? `${needsCount} thing${needsCount === 1 ? '' : 's'} waiting on you across ${projectsWithItems} project${projectsWithItems === 1 ? '' : 's'}.`
                : "Nothing's waiting on you right now."}
            </p>
          </div>
          {canCreateProject && (
            <Link to={projectsHref} style={{ ...btn('primary'), display: 'grid', placeItems: 'center', textDecoration: 'none', height: 36 }}>
              New project
            </Link>
          )}
        </div>

        {/* main column --------------------------------------------------- */}
        <div style={{ minWidth: 0 }}>
          {/* Brand-new member, or an admin who participates in nothing:
              Needs you and Waiting on others are hidden entirely. */}
          {!isParticipant ? (
            <div className="home-card" style={{ padding: 20 }}>
              {accessCheck.data?.isAdminSomewhere ? (
                <>
                  <h2 style={{ margin: 0, fontSize: 15, fontWeight: 600, color: 'var(--ink)' }}>Nothing to action yet</h2>
                  <p style={{ margin: '8px 0 0', fontSize: 13.5, lineHeight: 1.6, color: 'var(--muted)' }}>
                    You&apos;re a workspace admin, so you can view every project, but you&apos;re not a
                    participant on any. You&apos;ll only see items to action here once you&apos;re added to a project.
                  </p>
                  <p style={{ margin: '12px 0 0', fontSize: 13.5 }}>
                    <Link to={projectsHref} className="auth-link">Browse projects</Link>
                  </p>
                </>
              ) : (
                <>
                  <h2 style={{ margin: 0, fontSize: 15, fontWeight: 600, color: 'var(--ink)' }}>
                    You&apos;re in {workspace.data?.name ?? 'this workspace'}
                  </h2>
                  <p style={{ margin: '8px 0 0', fontSize: 13.5, lineHeight: 1.6, color: 'var(--muted)' }}>
                    Projects you&apos;re added to will show up here.
                  </p>
                  {canCreateProject && (
                    <Link to={projectsHref} style={{ ...btn('primary'), display: 'inline-grid', placeItems: 'center', textDecoration: 'none', marginTop: 14 }}>
                      Create a project
                    </Link>
                  )}
                </>
              )}
            </div>
          ) : (
            <>
              <Section
                title="Needs you"
                action={needsCount > NEEDS_YOU_CAP ? <Link to={projectsHref} className="auth-link" style={{ fontSize: 12.5 }}>View all ({needsCount})</Link> : undefined}
              >
                {approvals.isError || reviews.isError ? (
                  <SectionError onRetry={() => { approvals.refetch(); reviews.refetch() }} />
                ) : parts.isLoading || approvals.isLoading || reviews.isLoading ? (
                  <Rows><div style={{ padding: 14 }}><Skeleton className="h-8 w-full" /></div></Rows>
                ) : needsCount === 0 ? (
                  <div className="home-card" style={{ padding: 18, display: 'flex', alignItems: 'center', gap: 9 }}>
                    <Check size={15} aria-hidden="true" style={{ color: 'var(--status-approved)' }} />
                    <span style={{ fontSize: 13.5, color: 'var(--muted)' }}>Nothing&apos;s waiting on you.</span>
                  </div>
                ) : (
                  <Rows>
                    {needsYou.slice(0, NEEDS_YOU_CAP).map((item) =>
                      item.kind === 'approval' ? (
                        <div
                          key={item.slotId}
                          className="home-row"
                          style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '13px 14px', borderLeft: '3px solid var(--accent)', flexWrap: 'wrap' }}
                        >
                          <div style={{ minWidth: 0, flex: 1 }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                              <span className="auth-mono" style={{ fontSize: 11.5, color: 'var(--faint)' }}>{item.code}</span>
                              <Link to={`/workspace/${workspaceId}/project/${item.projectId}/approval/${item.requestId}`} style={{ fontSize: 14, color: 'var(--ink)', textDecoration: 'none', fontWeight: 500 }}>
                                {item.title}
                              </Link>
                              <Chip label="approver" tone="approver" />
                              <CapacityChip capacity={item.capacity} />
                            </div>
                            <p style={{ margin: '4px 0 0', fontSize: 12.5, color: 'var(--muted)' }}>
                              {item.projectName}
                              {item.sentByName ? ` · sent by ${item.sentByName}` : ''}
                              {item.dueAt ? ` · due ${relative(item.dueAt)}` : ''}
                            </p>
                          </div>
                          <div style={{ display: 'flex', gap: 8 }}>
                            <button
                              className="home-action"
                              style={btn('primary')}
                              disabled={respond.isPending}
                              aria-label={`Approve ${item.code} ${item.title}`}
                              onClick={() => doRespond(item, 'approved')}
                            >
                              Approve
                            </button>
                            <button
                              className="home-action"
                              style={btn('secondary')}
                              disabled={respond.isPending}
                              aria-label={`Request changes on ${item.code} ${item.title}`}
                              onClick={() => setDialogFor(item)}
                            >
                              Request changes
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div key={item.participantId} className="home-row" style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '13px 14px', flexWrap: 'wrap' }}>
                          <div style={{ minWidth: 0, flex: 1 }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                              <span className="auth-mono" style={{ fontSize: 11.5, color: 'var(--faint)' }}>{item.code}</span>
                              <span style={{ fontSize: 14, color: 'var(--ink)', fontWeight: 500 }}>{item.title}</span>
                              <Chip label="reviewer" />
                              <CapacityChip capacity={item.capacity} />
                            </div>
                            <p style={{ margin: '4px 0 0', fontSize: 12.5, color: 'var(--muted)' }}>
                              {item.projectName} · review opened {relative(item.openedAt)}
                            </p>
                          </div>
                          {/* Reviewers comment; they never approve. No inline decision here. */}
                          <Link
                            className="home-action"
                            to={`/workspace/${workspaceId}/project/${item.projectId}/review/${item.reviewId}`}
                            style={{ ...btn('secondary'), display: 'grid', placeItems: 'center', textDecoration: 'none' }}
                          >
                            Open review
                          </Link>
                        </div>
                      ),
                    )}
                  </Rows>
                )}
              </Section>

              <Section title="Waiting on others">
                {waiting.isError ? (
                  <SectionError onRetry={() => waiting.refetch()} />
                ) : waiting.isLoading ? (
                  <Rows><div style={{ padding: 14 }}><Skeleton className="h-8 w-full" /></div></Rows>
                ) : (waiting.data ?? []).length === 0 ? (
                  <div className="home-card" style={{ padding: 18, fontSize: 13.5, color: 'var(--muted)' }}>
                    Nothing of yours is blocked on someone else.
                  </div>
                ) : (
                  <Rows>
                    {(waiting.data ?? []).slice(0, WAITING_CAP).map((w) => {
                      const days = daysPending(w.pendingSince)
                      const stale = days >= STALE_AFTER_DAYS
                      return (
                        <div key={w.id} className="home-row" style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '12px 14px', flexWrap: 'wrap' }}>
                          <div style={{ minWidth: 0, flex: 1 }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                              <span className="auth-mono" style={{ fontSize: 11.5, color: 'var(--faint)' }}>{w.code}</span>
                              <span style={{ fontSize: 13.5, color: 'var(--ink)' }}>{w.title}</span>
                            </div>
                            <p style={{ margin: '3px 0 0', fontSize: 12.5, color: 'var(--muted)' }}>
                              {w.projectName} · {w.blockerName} · {w.blockerCapacity} {w.blockerRole}
                              {w.othersCount > 0 ? ` +${w.othersCount} more` : ''}
                            </p>
                          </div>
                          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <span aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', background: stale ? 'var(--status-changes)' : 'var(--status-superseded)' }} />
                            <span style={{ fontSize: 12.5, color: stale ? 'var(--status-changes-text)' : 'var(--faint)' }}>
                              {days === 0 ? 'today' : `${days} day${days === 1 ? '' : 's'} pending`}
                            </span>
                          </span>
                        </div>
                      )
                    })}
                  </Rows>
                )}
              </Section>
            </>
          )}
        </div>

        {/* right rail ---------------------------------------------------- */}
        <div style={{ minWidth: 0 }}>
          <Section
            title="Your projects"
            action={cards.length > PROJECTS_CAP ? <Link to={projectsHref} className="auth-link" style={{ fontSize: 12.5 }}>View all</Link> : undefined}
          >
            {parts.isError ? (
              <SectionError onRetry={() => parts.refetch()} />
            ) : parts.isLoading ? (
              <Rows><div style={{ padding: 14 }}><Skeleton className="h-8 w-full" /></div></Rows>
            ) : cards.length === 0 ? (
              <div className="home-card" style={{ padding: 16, fontSize: 13, lineHeight: 1.6, color: 'var(--muted)' }}>
                {accessCheck.data?.isAdminSomewhere
                  ? <>You&apos;re a workspace admin, so you can view every project, but you&apos;re not a participant on any. You&apos;ll only see items to action here once you&apos;re added to a project. <Link to={projectsHref} className="auth-link">Projects</Link></>
                  : <>Projects you&apos;re added to will appear here.</>}
              </div>
            ) : (
              <Rows>
                {cards.slice(0, PROJECTS_CAP).map((c) => {
                  const n = c.approvalsForMe + c.reviewsForMe
                  const summary =
                    c.approvalsForMe > 0
                      ? `${c.approvalsForMe} approval${c.approvalsForMe === 1 ? '' : 's'} awaiting you`
                      : c.reviewsForMe > 0
                        ? `${c.reviewsForMe} review${c.reviewsForMe === 1 ? '' : 's'} open for you`
                        : 'Nothing needs you'
                  return (
                    <Link
                      key={c.projectId}
                      to={`/workspace/${workspaceId}/project/${c.projectId}/overview`}
                      className="home-row"
                      style={{ display: 'block', padding: '12px 14px', textDecoration: 'none' }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'space-between' }}>
                        <span style={{ fontSize: 13.5, color: 'var(--ink)', fontWeight: 500, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {c.projectName}
                        </span>
                        <Chip label={c.role} tone={c.role === 'approver' ? 'approver' : 'default'} />
                      </div>
                      <p style={{ margin: '3px 0 0', fontSize: 12.5, color: n > 0 ? 'var(--status-changes-text)' : 'var(--faint)' }}>
                        {summary}
                      </p>
                    </Link>
                  )
                })}
              </Rows>
            )}
          </Section>

          <Section
            title="Recent activity"
            action={<Link to={`/workspace/${workspaceId}/inbox`} className="auth-link" style={{ fontSize: 12.5 }}>Full activity log</Link>}
          >
            {activity.isError ? (
              <SectionError onRetry={() => activity.refetch()} />
            ) : activity.isLoading ? (
              <Rows><div style={{ padding: 14 }}><Skeleton className="h-8 w-full" /></div></Rows>
            ) : (activity.data ?? []).length === 0 ? (
              <div className="home-card" style={{ padding: 16, fontSize: 13, color: 'var(--muted)' }}>Nothing yet.</div>
            ) : (
              <Rows>
                {(activity.data ?? []).map((a) => {
                  const dot = a.eventType.includes('approved') || a.eventType.endsWith('.activated')
                    ? 'var(--status-approved)'
                    : a.eventType.includes('uploaded') || a.eventType.includes('changes') || a.eventType.includes('published')
                      ? 'var(--status-changes)'
                      : 'var(--status-superseded)'
                  return (
                    <div key={a.id} className="home-row" style={{ display: 'flex', gap: 9, alignItems: 'flex-start', padding: '11px 14px' }}>
                      <span aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', background: dot, marginTop: 6, flex: '0 0 7px' }} />
                      <div style={{ minWidth: 0 }}>
                        <p style={{ margin: 0, fontSize: 13, color: 'var(--text)' }}>
                          <strong style={{ fontWeight: 500 }}>{a.actorName ?? 'Someone'}</strong>{' '}
                          {a.eventType.split('.').slice(-1)[0]?.replace(/_/g, ' ')}{' '}
                          <span className="auth-mono" style={{ fontSize: 11.5, color: 'var(--faint)' }}>{a.subjectLabel ?? ''}</span>
                        </p>
                        <p style={{ margin: '2px 0 0', fontSize: 11.5, color: 'var(--faint)' }}>{relative(a.occurredAt)}</p>
                      </div>
                    </div>
                  )
                })}
              </Rows>
            )}
          </Section>
        </div>
      </div>

      <RequestChangesDialog
        item={dialogFor}
        onClose={() => setDialogFor(null)}
        onSubmit={(comment) => {
          if (dialogFor) doRespond(dialogFor, 'changes_requested', comment)
          setDialogFor(null)
        }}
      />
    </>
  )
}
