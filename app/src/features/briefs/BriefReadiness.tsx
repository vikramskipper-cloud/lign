import { Link } from 'react-router'
import { Button } from '@/features/planning/PlanningButton'
import type {
  BriefRevision,
  ProjectBriefData,
  BriefReadinessContext,
} from './queries'
import {
  briefReadiness,
  type ReadinessCheck,
  type ReadinessTarget,
} from './readiness'
import type { BriefDocument } from './model'
const help = 'text-xs leading-relaxed text-[#786b60]'
export default function BriefReadiness({
  data,
  document,
  respondent,
  metadata,
  metadataError,
  checking,
  dirty,
  stale,
  areaDirty,
  uploading,
  loadedVersion,
  busy,
  canEdit,
  revision,
  workspaceId,
  projectId,
  onAction,
  onReturnToDraft,
}: {
  data: ProjectBriefData
  document: BriefDocument
  respondent: string
  metadata?: BriefReadinessContext
  metadataError: boolean
  checking: boolean
  dirty: boolean
  stale: boolean
  areaDirty: boolean
  uploading: boolean
  loadedVersion: number
  busy: boolean
  canEdit: boolean
  revision?: BriefRevision
  workspaceId: string
  projectId: string
  onAction: (target: ReadinessTarget) => void
  onReturnToDraft: () => void
}) {
  const result = briefReadiness({
    data,
    document,
    respondent,
    metadata,
    metadataError,
    checking,
    dirty,
    stale,
    areaDirty,
    uploading,
    loadedVersion,
  })
  if (revision)
    return (
      <section
        aria-label="Saved brief package"
        className="space-y-3 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5"
      >
        <h2 className="text-lg font-semibold">
          Saved package · revision {revision.number}
        </h2>
        <p className="text-sm text-[#786b60]">
          Readiness was checked when leadership requested agreement. This
          package is fixed; later references, assignments and draft edits do not
          change it.
        </p>
        <p className="text-sm">
          {
            revision.document.items.filter(
              (i) => i.kind === 'mandatory' || i.kind === 'preference',
            ).length
          }{' '}
          requirements/preferences ·{' '}
          {revision.document.items.filter((i) => i.kind === 'question').length}{' '}
          recorded questions ·{' '}
          {revision.document.referenceSelection?.length ?? 0} selected
          references · {revision.document.references.length} brief links ·{' '}
          {revision.attachments.length} attached files
        </p>
      </section>
    )
  const blockers = result.checks.filter((c) => c.state === 'block'),
    pending = result.checks.filter((c) => c.state === 'pending'),
    suggestions = result.checks.filter((c) => c.state === 'suggestion'),
    completed = result.checks.filter((c) => c.state === 'pass')
  const approver = metadata?.approver?.name,
    headline = result.pending
      ? 'Checking agreement readiness…'
      : result.clientReady
        ? data.canManage
          ? `Ready to request agreement${approver ? ' from ' + approver : ''}`
          : `Ready for leadership to request agreement${approver ? ' from ' + approver : ''}`
        : `Resolve ${blockers.length} ${blockers.length === 1 ? 'issue' : 'issues'} before requesting agreement`
  const links = {
    boards: `/workspace/${workspaceId}/project/${projectId}/references?stage=direction`,
    people: `/workspace/${workspaceId}/project/${projectId}/people`,
  }
  const row = (check: ReadinessCheck) => {
    const actions = check.actions?.filter(
      (a) =>
        a.permission === 'view' ||
        (a.permission === 'edit' && canEdit) ||
        (a.permission === 'manage' && data.canManage),
    )
    const action = (a: NonNullable<ReadinessCheck['actions']>[number]) =>
      a.target.kind === 'boards' || a.target.kind === 'people' ? (
        <Link
          key={a.label}
          className="auth-link block break-words text-sm"
          to={links[a.target.kind]}
        >
          {a.label}
        </Link>
      ) : (
        <button
          key={a.label}
          type="button"
          className="auth-link block break-words text-left text-sm"
          disabled={
            busy ||
            (a.target.kind === 'save' && (stale || areaDirty || uploading))
          }
          onClick={() => onAction(a.target)}
        >
          {a.label}
        </button>
      )
    return (
      <li
        key={check.id}
        className="space-y-2 rounded-lg border border-[#e5ddd3] bg-white p-3"
      >
        <p className="text-sm font-semibold">{check.title}</p>
        <p className={help}>{check.detail}</p>
        <p className={help}>Responsible: {check.responsible}</p>
        {actions?.slice(0, 3).map(action)}
        {actions && actions.length > 3 && (
          <details>
            <summary className="auth-link cursor-pointer text-sm">
              Show all {actions.length} affected items
            </summary>
            <div className="mt-2 space-y-2">{actions.slice(3).map(action)}</div>
          </details>
        )}
        {!actions?.length &&
          check.actions?.some((a) => a.permission === 'edit') && (
            <p className={help}>
              {data.brief?.status === 'submitted'
                ? 'Leadership can return this brief to draft to make changes.'
                : 'An editable project team member can resolve this.'}
            </p>
          )}
      </li>
    )
  }
  return (
    <section
      aria-label="Brief readiness"
      className="space-y-4 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5"
    >
      <header className="space-y-2">
        <h2 className="text-lg font-semibold">Readiness check</h2>
        <p role="status" className="text-sm font-semibold">
          {headline}
        </p>
        <p className={help}>
          {data.brief?.status === 'submitted'
            ? 'The brief is submitted for team review.'
            : result.teamReady
              ? 'The saved overall needs can go to team review.'
              : 'Save the overall needs and resolve the team-review blockers first.'}{' '}
          Client agreement also requires the remaining checks below.
        </p>
      </header>
      {data.canManage &&
        data.brief?.status === 'submitted' &&
        blockers.length > 0 && (
          <Button variant="secondary" disabled={busy} onClick={onReturnToDraft}>
            Return to draft to make changes
          </Button>
        )}
      {result.automatic && result.automatic.items.length > 0 && (
        <aside
          aria-label="Automatic responsibility"
          className="space-y-2 rounded-lg bg-[#f3eee6] p-3"
        >
          <p className="text-sm">
            <strong>Automatic assignment:</strong>{' '}
            {result.automatic.person.name} (
            {result.automatic.person.role === 'lead'
              ? 'project lead'
              : 'contributor'}
            ) will be assigned to {result.automatic.items.length}{' '}
            {result.automatic.items.length === 1 ? 'commitment' : 'commitments'}{' '}
            when leadership requests agreement.
          </p>
          {canEdit && (
            <div className="flex flex-wrap gap-2">
              {result.automatic.items.slice(0, 3).map((i) => (
                <button
                  key={i.id}
                  className="auth-link text-sm"
                  disabled={busy}
                  onClick={() =>
                    onAction({ kind: 'item', id: i.id, field: 'owner' })
                  }
                >
                  Change assignment: {i.title}
                </button>
              ))}
              {result.automatic.items.length > 3 && (
                <details className="w-full">
                  <summary className="auth-link cursor-pointer text-sm">
                    Show all {result.automatic.items.length} automatic
                    assignments
                  </summary>
                  <div className="mt-2 flex flex-col items-start gap-2">
                    {result.automatic.items.slice(3).map((i) => (
                      <button
                        key={i.id}
                        className="auth-link text-left text-sm"
                        disabled={busy}
                        onClick={() =>
                          onAction({ kind: 'item', id: i.id, field: 'owner' })
                        }
                      >
                        Change assignment: {i.title}
                      </button>
                    ))}
                  </div>
                </details>
              )}
            </div>
          )}
        </aside>
      )}
      {(blockers.length > 0 || pending.length > 0) && (
        <section aria-label="Blocking client agreement" className="space-y-2">
          <h3 className="text-sm font-semibold">
            Blocking client agreement ({blockers.length + pending.length})
          </h3>
          <ul className="space-y-3">{[...blockers, ...pending].map(row)}</ul>
        </section>
      )}
      {suggestions.length > 0 && (
        <section aria-label="Optional improvements" className="space-y-2">
          <h3 className="text-sm font-semibold">
            Optional improvements ({suggestions.length})
          </h3>
          <p className={help}>
            These suggestions do not prevent team review or client agreement.
          </p>
          <ul className="space-y-3">{suggestions.map(row)}</ul>
        </section>
      )}
      <details>
        <summary className="auth-link cursor-pointer text-sm">
          Completed checks ({completed.length})
        </summary>
        <ul className="mt-3 space-y-3">{completed.map(row)}</ul>
      </details>
    </section>
  )
}
