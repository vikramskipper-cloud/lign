import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import { Button } from '@/features/planning/PlanningButton'
import { useBriefFeedback, type BriefFeedbackItem } from './feedbackQueries'
import type { ProjectBriefData } from './queries'
import type { ReadinessTarget } from './readiness'
const panel = 'space-y-4 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5',
  help = 'text-xs leading-relaxed text-[#786b60]'
const at = (date: string) => new Date(date).toLocaleString()
function FeedbackRow({
  item,
  canAddress,
  savedReady,
  busy,
  act,
  view,
  fix,
  targetLabel,
}: {
  item: BriefFeedbackItem
  canAddress: boolean
  savedReady: boolean
  busy: boolean
  act: (item: BriefFeedbackItem, action: string, note: string) => void
  view: (id: string) => void
  fix?: () => void
  targetLabel: string
}) {
  const [note, setNote] = useState('')
  return (
    <article
      aria-label={'Feedback: ' + item.body}
      className="space-y-3 rounded-lg border border-[#e5ddd3] bg-white p-4"
    >
      <p className="text-xs font-semibold uppercase text-[#786b60]">
        {item.status === 'verified'
          ? 'Client verified'
          : item.status === 'addressed'
            ? 'Team responded · awaiting client verification'
            : 'Open · team response needed'}
      </p>
      <p className="whitespace-pre-wrap break-words text-sm font-semibold">
        {item.body}
      </p>
      <p className={help}>
        {targetLabel} · Revision {item.sourceNumber} · Logged by{' '}
        {item.creatorName} · {at(item.createdAt)}
      </p>
      <div className="flex flex-wrap gap-3">
        <button
          className="auth-link text-sm"
          disabled={!savedReady || busy}
          onClick={() => view(item.sourceRevisionId)}
        >
          View source revision {item.sourceNumber}
        </button>
        {fix && (
          <button className="auth-link text-sm" disabled={busy} onClick={fix}>
            Open affected item
          </button>
        )}
      </div>
      {item.response && (
        <blockquote className="space-y-2 border-l-2 border-[#d9622b] pl-3">
          <p className="whitespace-pre-wrap break-words text-sm">
            {item.response}
          </p>
          <p className={help}>
            Team response by {item.addressedBy}
            {item.responseNumber
              ? ` · Revision ${item.responseNumber}`
              : ' · Saved working draft'}
            {item.addressedAt ? ' · ' + at(item.addressedAt) : ''}
          </p>
          {item.responseRevisionId && (
            <button
              className="auth-link text-sm"
              disabled={!savedReady || busy}
              onClick={() => view(item.responseRevisionId!)}
            >
              View response revision {item.responseNumber}
            </button>
          )}
        </blockquote>
      )}
      {item.stale && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          The brief changed since this response. The team must update its
          response against the current saved brief before client verification.
        </p>
      )}
      {item.status === 'addressed' &&
        !item.responseRevisionId &&
        !item.stale && (
          <p className={help}>
            This response is saved against the working draft. Request agreement
            on this saved version to include it in the client's review.
          </p>
        )}
      {item.status === 'verified' && (
        <p className="text-sm">
          Verified by {item.verifiedBy} on revision {item.verifiedNumber}
          {item.verifiedAt ? ' · ' + at(item.verifiedAt) : ''}.
        </p>
      )}
      {((canAddress && item.status !== 'verified') ||
        item.canVerify ||
        item.canReopen) && (
        <div className="space-y-2">
          <label className="block text-sm">
            {canAddress ? 'Team response' : 'Verification or further changes'}
            <textarea
              className="auth-field mt-1 w-full"
              rows={3}
              maxLength={5000}
              disabled={busy}
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </label>
          <div className="flex flex-wrap gap-2">
            {canAddress && item.status !== 'verified' && (
              <Button
                disabled={busy || !savedReady || !note.trim()}
                onClick={() => act(item, 'address', note)}
              >
                Mark addressed by team
              </Button>
            )}
            {item.canVerify && (
              <Button
                disabled={busy || !savedReady || !note.trim()}
                onClick={() => act(item, 'verify', note)}
              >
                Verify response on revision {item.responseNumber}
              </Button>
            )}
            {item.canReopen && (
              <Button
                variant="secondary"
                disabled={busy || !savedReady || !note.trim()}
                onClick={() => act(item, 'reopen', note)}
              >
                Request further changes
              </Button>
            )}
          </div>
          {!savedReady && (
            <p className={help}>
              Save or cancel local edits before recording a feedback response.
            </p>
          )}
          {item.canReopen && (
            <p className={help}>
              Requesting further changes reopens this feedback. An agreed brief
              stays fixed until leadership starts a new revision.
            </p>
          )}
        </div>
      )}
      <details>
        <summary className="auth-link cursor-pointer text-sm">
          Feedback history ({item.events.length})
        </summary>
        <ol className="mt-2 space-y-2">
          {item.events.map((event, i) => (
            <li key={i} className="text-xs text-[#786b60]">
              <strong>{event.action.replaceAll('_', ' ')}</strong> ·{' '}
              {event.actorName}
              {event.revisionNumber
                ? ` · Revision ${event.revisionNumber}`
                : ''}{' '}
              · {at(event.at)}
              {event.note && (
                <p className="mt-1 whitespace-pre-wrap break-words">
                  {event.note}
                </p>
              )}
            </li>
          ))}
        </ol>
      </details>
    </article>
  )
}
export default function BriefFeedbackTracker({
  projectId,
  data,
  savedReady,
  briefVersion,
  canEdit,
  onEdit,
  onView,
}: {
  projectId: string
  data: ProjectBriefData
  savedReady: boolean
  briefVersion: number
  canEdit: boolean
  onEdit: (target: ReadinessTarget) => void
  onView: (revisionId: string) => void
}) {
  const query = useBriefFeedback(projectId),
    qc = useQueryClient(),
    [error, setError] = useState(''),
    [source, setSource] = useState(''),
    [kind, setKind] = useState('overall'),
    [target, setTarget] = useState(''),
    [body, setBody] = useState(''),
    [showVerified, setShowVerified] = useState(false)
  const mutation = useMutation({
    mutationFn: async ({
      rpc,
      args,
    }: {
      rpc: string
      args: Record<string, unknown>
    }) => {
      const r = await supabase.rpc(rpc, { p_project_id: projectId, ...args })
      if (r.error) throw r.error
      return r.data
    },
    onSuccess: async (_, input) => {
      setError('')
      if (input.rpc === 'add_brief_feedback_item') {
        setBody('')
        setTarget('')
        setKind('overall')
      }
      await Promise.all([
        qc.invalidateQueries({ queryKey: ['brief-feedback'] }),
        qc.invalidateQueries({ queryKey: ['project-brief'] }),
      ])
    },
    onError: (e) => {
      setError(humanizeError(e))
      void query.refetch()
    },
  })
  const items = query.data?.rows ?? [],
    sources = query.data?.canCreateFor ?? [],
    sourceId = sources.some((r) => r.id === source)
      ? source
      : (sources[0]?.id ?? ''),
    sourceDocument = data.revisions.find((r) => r.id === sourceId)?.document
  if (query.isSuccess && !items.length && !sources.length) return null
  const options =
    kind === 'field'
      ? sourceDocument?.fields
      : kind === 'item'
        ? sourceDocument?.items
        : kind === 'reference'
          ? sourceDocument?.references
          : []
  const targetInfo = (item: BriefFeedbackItem) => {
    const doc = data.revisions.find(
      (r) => r.id === item.sourceRevisionId,
    )?.document
    const current = data.brief?.document
    let label = 'Overall brief',
      fix: ReadinessTarget | undefined
    if (item.targetKind === 'field') {
      label =
        doc?.fields.find((f) => f.id === item.targetId)?.label ??
        'Recorded brief question'
      if (current?.fields.some((f) => f.id === item.targetId))
        fix = { kind: 'field', id: item.targetId! }
    }
    if (item.targetKind === 'item') {
      label =
        doc?.items.find((i) => i.id === item.targetId)?.title ??
        'Recorded brief item'
      if (current?.items.some((i) => i.id === item.targetId))
        fix = { kind: 'item', id: item.targetId!, field: 'detail' }
    }
    if (item.targetKind === 'reference') {
      label =
        doc?.references.find((r) => r.id === item.targetId)?.label ??
        'Recorded brief link'
      if (current?.references.some((r) => r.id === item.targetId))
        fix = { kind: 'reference', id: item.targetId!, field: 'url' }
    }
    return { label, fix: canEdit && fix ? () => onEdit(fix!) : undefined }
  }
  return (
    <section aria-label="Brief feedback tracking" className={panel}>
      <h2 className="text-lg font-semibold">Feedback and responses</h2>
      <p className="text-sm text-[#786b60]">
        The team records how it addressed each request. The client who requested
        the changes verifies the response on a specific saved revision. Agreeing
        the brief does not automatically verify individual feedback.
      </p>
      {query.isPending ? (
        <p role="status">Loading feedback…</p>
      ) : query.isError ? (
        <p role="alert">
          Could not load feedback.{' '}
          <button className="auth-link" onClick={() => void query.refetch()}>
            Retry feedback
          </button>
        </p>
      ) : (
        <>
          <p role="status" className="text-sm font-semibold">
            {items.filter((i) => i.status !== 'verified').length} feedback items
            awaiting resolution ·{' '}
            {items.filter((i) => i.status === 'verified').length} client
            verified
          </p>
          {error && (
            <p role="alert" className="text-sm text-red-700">
              {error}
            </p>
          )}
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={showVerified}
              onChange={(e) => setShowVerified(e.target.checked)}
            />
            Show verified feedback
          </label>
          {items
            .filter((i) => showVerified || i.status !== 'verified')
            .map((item) => {
              const target = targetInfo(item)
              return (
                <FeedbackRow
                  key={item.id + item.version}
                  item={item}
                  canAddress={Boolean(query.data?.canAddress)}
                  savedReady={savedReady}
                  busy={mutation.isPending || query.isFetching}
                  targetLabel={target.label}
                  fix={target.fix}
                  view={onView}
                  act={(i, action, note) =>
                    mutation.mutate({
                      rpc: 'act_on_brief_feedback',
                      args: {
                        p_feedback_id: i.id,
                        p_expected_version: i.version,
                        p_action: action,
                        p_note: note,
                        p_expected_brief_version: briefVersion,
                        p_review_revision_id:
                          action === 'verify' ? i.responseRevisionId : null,
                      },
                    })
                  }
                />
              )
            })}
          {sources.length > 0 && (
            <details>
              <summary className="auth-link cursor-pointer font-medium">
                Add a specific feedback item
              </summary>
              <div className="mt-3 space-y-3">
                <label className="block text-sm">
                  Original change request
                  <select
                    className="auth-field mt-1 w-full"
                    aria-label="Original change request"
                    value={sourceId}
                    onChange={(e) => {
                      setSource(e.target.value)
                      setTarget('')
                    }}
                  >
                    {sources.map((r) => (
                      <option key={r.id} value={r.id}>
                        Revision {r.number}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="block text-sm">
                  Feedback concerns
                  <select
                    className="auth-field mt-1 w-full"
                    aria-label="Feedback concerns"
                    value={kind}
                    onChange={(e) => {
                      setKind(e.target.value)
                      setTarget('')
                    }}
                  >
                    <option value="overall">Overall brief</option>
                    <option value="field">A brief question</option>
                    <option value="item">
                      A requirement, preference or question
                    </option>
                    <option value="reference">A brief link</option>
                  </select>
                </label>
                {kind !== 'overall' && (
                  <label className="block text-sm">
                    Affected item
                    <select
                      className="auth-field mt-1 w-full"
                      aria-label="Affected item"
                      value={target}
                      onChange={(e) => setTarget(e.target.value)}
                    >
                      <option value="">Choose from the source revision</option>
                      {options?.map((o) => (
                        <option key={o.id} value={o.id}>
                          {'label' in o ? o.label : o.title}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                <label className="block text-sm">
                  Requested change
                  <textarea
                    className="auth-field mt-1 w-full"
                    rows={3}
                    maxLength={5000}
                    value={body}
                    onChange={(e) => setBody(e.target.value)}
                  />
                </label>
                <Button
                  disabled={
                    mutation.isPending ||
                    !savedReady ||
                    !body.trim() ||
                    (kind !== 'overall' && !target)
                  }
                  onClick={() =>
                    mutation.mutate({
                      rpc: 'add_brief_feedback_item',
                      args: {
                        p_source_revision_id: sourceId,
                        p_body: body,
                        p_target_kind: kind,
                        p_target_id: kind === 'overall' ? null : target,
                      },
                    })
                  }
                >
                  Add feedback item
                </Button>
              </div>
            </details>
          )}
        </>
      )}
    </section>
  )
}
