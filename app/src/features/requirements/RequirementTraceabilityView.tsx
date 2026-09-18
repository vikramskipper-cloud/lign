import { Link } from 'react-router'
import { EmptyState } from '@/ui/empty-state'
import { Skeleton } from '@/ui/skeleton'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { PriorityBadge } from './PriorityBadge'
import { useRequirementTrace } from './queries'
import { relative, absolute } from '@/lib/formatDate'

interface Props {
  workspaceId: string
  projectId: string
  requirementId: string
}

/** APP 008 §11.3 / §15: traceability tab body — renders the bundled trace RPC. */
export function RequirementTraceabilityView({
  workspaceId,
  projectId,
  requirementId,
}: Props) {
  const q = useRequirementTrace(requirementId)
  if (q.isLoading) {
    return (
      <div className="space-y-2 p-3">
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-24 w-full" />
      </div>
    )
  }
  if (q.isError || !q.data) {
    return (
      <div className="p-3">
        <EmptyState title="Couldn't load traceability" />
      </div>
    )
  }
  const t = q.data
  return (
    <div className="space-y-4 p-3">
      <Section
        title={t.is_project_wide ? 'Applies to project-wide' : 'Applies to'}
        empty={t.is_project_wide ? undefined : 'No assets in this scope'}
      >
        {t.applicable_assets.length > 0 && (
          <ul className="flex flex-wrap gap-1.5">
            {t.applicable_assets.map((a) => (
              <li key={a.design_asset_id}>
                <Link
                  to={`/workspace/${workspaceId}/project/${projectId}/asset/${a.design_asset_id}`}
                  className="rounded-full border border-[--color-border] bg-[--color-surface-2] px-2 py-0.5 text-xs hover:border-[--color-border-strong]"
                >
                  {a.name ?? a.design_asset_id.slice(0, 8)}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section
        title="Sub-requirements"
        empty={t.sub_requirements.length === 0 ? 'No sub-requirements' : undefined}
      >
        <ul className="space-y-1">
          {t.sub_requirements.map((s) => (
            <li
              key={s.id}
              className="flex items-center gap-2 rounded-[--radius-sm] border border-[--color-border] px-2 py-1 text-xs"
            >
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/requirement/${s.id}`}
                className="min-w-0 flex-1 truncate hover:underline"
              >
                <span className="font-mono text-[10px] text-[--color-text-muted]">
                  {s.code}
                </span>{' '}
                {s.title}
              </Link>
              <PriorityBadge priority={s.priority} />
              <StateBadge state={s.status as WorkflowState} />
            </li>
          ))}
        </ul>
      </Section>

      <Section
        title="Assessments"
        empty={t.assessments.length === 0 ? 'No assessments yet' : undefined}
      >
        <ul className="space-y-1">
          {t.assessments.map((a) => (
            <li
              key={a.asset_version_id + a.assessed_at}
              className="rounded-[--radius-sm] border border-[--color-border] px-2 py-1 text-xs"
            >
              <div className="flex items-center gap-2">
                <span className="font-mono text-[10px] text-[--color-text-subtle]">
                  v{a.version_number ?? '?'}
                </span>
                <span className="font-medium">{a.status}</span>
                <span
                  className="ml-auto text-[10px] text-[--color-text-subtle]"
                  title={absolute(a.assessed_at)}
                >
                  {relative(a.assessed_at)}
                </span>
              </div>
              {a.note && (
                <p className="mt-1 text-[--color-text-muted]">{a.note}</p>
              )}
            </li>
          ))}
        </ul>
      </Section>

      <Section
        title="Related changes"
        empty={t.related_changes.length === 0 ? 'No linked changes' : undefined}
      >
        <ul className="space-y-1">
          {t.related_changes.map((c) => (
            <li
              key={c.change_id}
              className="rounded-[--radius-sm] border border-[--color-border] px-2 py-1 text-xs"
            >
              <span className="font-medium">{c.kind}</span>
              {c.subject_label && (
                <span className="ml-1 text-[--color-text-muted]">
                  {c.subject_label}
                </span>
              )}
              <span
                className="ml-2 text-[10px] text-[--color-text-subtle]"
                title={absolute(c.created_at)}
              >
                {relative(c.created_at)}
              </span>
            </li>
          ))}
        </ul>
      </Section>

      <Section
        title="Related decisions"
        empty={
          t.related_decisions.length === 0 ? 'No linked decisions' : undefined
        }
      >
        <ul className="space-y-1">
          {t.related_decisions.map((d) => (
            <li
              key={d.decision_id}
              className="rounded-[--radius-sm] border border-[--color-border] px-2 py-1 text-xs"
            >
              <span className="font-medium">{d.subject_kind}</span>
              {d.decision_reason_snippet && (
                <p className="mt-1 text-[--color-text-muted]">
                  {d.decision_reason_snippet}
                </p>
              )}
            </li>
          ))}
        </ul>
      </Section>

      <Section
        title="Approval history"
        empty={
          t.approval_requests.length === 0 ? 'No approvals cite this' : undefined
        }
      >
        <ul className="space-y-1">
          {t.approval_requests.map((ar) => (
            <li
              key={ar.approval_request_id}
              className="flex items-center gap-2 rounded-[--radius-sm] border border-[--color-border] px-2 py-1 text-xs"
            >
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/approval/${ar.approval_request_id}`}
                className="min-w-0 flex-1 truncate hover:underline"
              >
                {ar.approval_request_id.slice(0, 8)}…
              </Link>
              <StateBadge state={ar.status as WorkflowState} />
            </li>
          ))}
        </ul>
      </Section>

      <Section title="Supersession chain">
        <ul className="space-y-1">
          {t.supersession_chain.map((c) => (
            <li
              key={c.requirement_id}
              className={
                'flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-xs ' +
                (c.is_current
                  ? 'bg-[--color-surface-2] font-medium'
                  : 'hover:bg-[--color-surface-2]')
              }
            >
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/requirement/${c.requirement_id}`}
                className="min-w-0 flex-1 truncate"
              >
                <span className="font-mono text-[10px] text-[--color-text-muted]">
                  {c.code}
                </span>{' '}
                {c.title}
              </Link>
              <StateBadge state={c.status as WorkflowState} />
            </li>
          ))}
        </ul>
      </Section>

      <div className="rounded-[--radius-md] border border-dashed border-[--color-border] p-3 text-xs text-[--color-text-subtle]">
        Discussion count: {t.discussion_count}
      </div>
    </div>
  )
}

function Section({
  title,
  children,
  empty,
}: {
  title: string
  children?: React.ReactNode
  empty?: string
}) {
  return (
    <div className="space-y-1.5">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        {title}
      </div>
      {empty ? (
        <div className="rounded-[--radius-sm] border border-dashed border-[--color-border] px-2 py-1.5 text-xs text-[--color-text-subtle]">
          {empty}
        </div>
      ) : (
        children
      )}
    </div>
  )
}
