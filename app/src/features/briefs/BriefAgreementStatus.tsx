import { Link } from 'react-router'
import { Button } from '@/features/planning/PlanningButton'
import { briefAgreementStatus, type AgreementAction } from './agreementStatus'
import type { BriefRevision, ProjectBriefData } from './queries'
export default function BriefAgreementStatus({
  data,
  history,
  canPrepareProposal = false,
  checkingProposal = false,
  proposalError = false,
  retryProposal,
  workspaceId,
  projectId,
  busy,
  dirty,
  areaDirty,
  onAction,
}: {
  data: ProjectBriefData
  history?: BriefRevision
  canPrepareProposal?: boolean
  checkingProposal?: boolean
  proposalError?: boolean
  retryProposal?: () => void
  workspaceId: string
  projectId: string
  busy: boolean
  dirty: boolean
  areaDirty: boolean
  onAction: (action: Exclude<AgreementAction, 'proposal' | null>) => void
}) {
  const state = briefAgreementStatus(data, history, canPrepareProposal),
    checking = !history && state.phase === 'agreed' && checkingProposal
  return (
    <section
      aria-label={
        history ? 'Saved revision status' : 'Brief status and next action'
      }
      className={`space-y-3 rounded-xl border p-5 ${history || state.phase === 'changes_requested' ? 'border-[#e8c898] bg-[#fff7eb]' : 'border-[#e5ddd3] bg-[#fffdf9]'}`}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-wide text-[#786b60]">
            {state.revision}
          </p>
          <h2 className="mt-2 break-words text-xl font-semibold">
            {state.title}
          </h2>
        </div>
        {state.at && (
          <p className="text-xs text-[#786b60]">
            {state.atLabel}{' '}
            <time dateTime={state.at}>
              {new Date(state.at).toLocaleString(undefined, {
                dateStyle: 'medium',
                timeStyle: 'short',
              })}
            </time>
          </p>
        )}
      </div>
      <p className="text-sm text-[#786b60]">{state.description}</p>
      <p className="text-sm">
        <strong>Who acts next:</strong> {state.next}
      </p>
      {state.feedback && (
        <blockquote
          id="brief-change-feedback"
          tabIndex={-1}
          className="whitespace-pre-wrap break-words rounded-lg border border-[#e8c898] bg-white p-3 text-sm"
        >
          <p className="mb-1 font-semibold">Changes requested</p>
          <p>{state.feedback}</p>
        </blockquote>
      )}
      {!history && dirty && (
        <p className="text-sm text-[#8a4a17]">
          You have unsaved edits. They are not part of a client agreement
          request.
        </p>
      )}
      {!history && areaDirty && (
        <p className="text-sm text-[#8a4a17]">
          Save or cancel your area changes before moving to another step.
        </p>
      )}
      <div className="flex flex-wrap items-center gap-2">
        {checking ? (
          <p role="status" className="text-sm text-[#786b60]">
            Checking your next action…
          </p>
        ) : state.action === 'proposal' ? (
          busy || areaDirty ? (
            <Button disabled>{state.actionLabel}</Button>
          ) : (
            <Button asChild>
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/proposal`}
              >
                {state.actionLabel}
              </Link>
            </Button>
          )
        ) : (
          state.action && (
            <Button
              disabled={busy || areaDirty}
              onClick={() =>
                onAction(
                  state.action as Exclude<AgreementAction, 'proposal' | null>,
                )
              }
            >
              {state.actionLabel}
            </Button>
          )
        )}
        {state.action === 'feedback' && (
          <Button
            variant="secondary"
            disabled={busy || areaDirty}
            onClick={() => onAction('edit')}
          >
            Update brief
          </Button>
        )}
      </div>
      {proposalError && !history && state.phase === 'agreed' && (
        <p role="status" className="text-xs text-[#786b60]">
          Could not check proposal access.{' '}
          <button className="auth-link" onClick={retryProposal}>
            Retry
          </button>
        </p>
      )}
    </section>
  )
}
