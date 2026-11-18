import { useEffect, useState } from 'react'
import { Link } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import { invalidateRequirementsLists } from '@/features/shared/invalidate'
import { Button } from '@/features/planning/PlanningButton'
import {
  useBriefRequirementChanges,
  type RequirementChange,
} from './reconciliationQueries'
import type { BriefRevision } from './queries'
const panel = 'space-y-4 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5',
  help = 'text-xs leading-relaxed text-[#786b60]'
function ChangeRow({
  row,
  owners,
  removed,
  canManage,
  canRetire,
  busy,
  apply,
  match,
  unmatch,
  workspaceId,
  projectId,
}: {
  row: RequirementChange
  owners: { id: string; name: string }[]
  removed: RequirementChange[]
  canManage: boolean
  canRetire: boolean
  busy: boolean
  apply: (row: RequirementChange, action: string, note: string) => void
  match: (row: RequirementChange, old: RequirementChange) => void
  unmatch: (row: RequirementChange) => void
  workspaceId: string
  projectId: string
}) {
  const [ack, setAck] = useState(false),
    [note, setNote] = useState(''),
    [matchId, setMatchId] = useState('')
  useEffect(() => {
    setAck(false)
  }, [row.token])
  const impact =
      row.impact.assets + row.impact.assessments + row.impact.proposals,
    previousInactive = Boolean(
      row.previous && !['draft', 'active'].includes(row.previous.status),
    ),
    invalidDraft = Boolean(
      row.next && !['draft', 'active'].includes(row.next.status),
    ),
    restore = row.kind !== 'removed' && previousInactive,
    needsNote =
      row.manualEdits || impact > 0 || previousInactive || invalidDraft
  const requirement = (r: RequirementChange['previous'], label: string) =>
    r && (
      <div className="min-w-0 space-y-2">
        <h4 className="text-sm font-semibold">{label}</h4>
        <Link
          className="auth-link break-words text-sm"
          to={`/workspace/${workspaceId}/project/${projectId}/requirement/${r.id}`}
        >
          {r.code} · {r.content.title}
        </Link>
        <p className={help}>
          {r.status} · {r.content.priority} priority · Responsible:{' '}
          {owners.find((o) => o.id === r.content.owner_profile_id)?.name ??
            'Not in the current project directory'}
        </p>
        <p className="whitespace-pre-wrap break-words text-sm">
          {r.content.description}
        </p>
      </div>
    )
  return (
    <article
      aria-label={
        'Requirement change: ' +
        (row.proposedItem?.title ?? row.previousItem?.title ?? row.itemId)
      }
      className="space-y-3 rounded-lg border border-[#e5ddd3] bg-white p-4"
    >
      <p className="text-xs font-semibold uppercase text-[#786b60]">
        {row.kind} ·{' '}
        {row.state === 'matched'
          ? 'Matched to replacement'
          : row.state === 'applied'
            ? row.outcome
            : 'Awaiting leadership review'}
      </p>
      <h3 className="font-semibold">
        {row.proposedItem?.title ?? row.previousItem?.title}
      </h3>
      <div className="grid gap-4 sm:grid-cols-2">
        {requirement(row.previous, 'Existing requirement')}
        {row.next?.id !== row.previous?.id &&
          requirement(row.next, 'Proposed requirement')}
      </div>
      {row.kind === 'unchanged' && (
        <p className="text-sm">
          The existing requirement carries forward without creating another
          copy.
        </p>
      )}
      {row.kind === 'removed' && (
        <p className="text-sm">
          This commitment was removed from the brief. Confirm retirement, retain
          it independently with a reason, or match it to a recreated item.
        </p>
      )}
      {row.next && !row.responsibilityValid && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          Assign an active project lead or contributor to the proposed
          requirement before activation. Open its requirement record to update
          responsibility, then review again.
        </p>
      )}
      {row.manualEdits && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          Manual edits detected. Review the current requirement and proposed
          content, and explain your decision.
        </p>
      )}
      {restore && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          The earlier requirement was retired or replaced independently.
          Activating this as a new requirement leaves that earlier lineage
          unchanged. Review it before proceeding.
        </p>
      )}
      {impact > 0 && (
        <p className="text-sm">
          Linked work: {row.impact.assets} design assets,{' '}
          {row.impact.assessments} assessments, {row.impact.proposals} saved
          proposals. These records stay attached to the existing requirement.
          Review the new requirement against that work separately.
        </p>
      )}
      {row.kind === 'removed' && previousInactive && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          The existing requirement was already retired or replaced
          independently. Confirm its recorded retirement or retain its
          independent replacement lineage with a review note.
        </p>
      )}
      {invalidDraft && (
        <p role="alert" className="text-sm text-[#8a4a17]">
          The proposed draft was retired independently. You can prepare a fresh
          draft from the agreed brief while preserving the retired record.
        </p>
      )}
      {row.note && (
        <p className="whitespace-pre-wrap break-words text-sm">
          <strong>Review note:</strong> {row.note}
        </p>
      )}
      {canManage && row.state === 'pending' && (
        <div className="space-y-3">
          {row.matchedFrom && (
            <Button
              variant="secondary"
              disabled={busy}
              onClick={() => unmatch(row)}
            >
              Undo replacement match
            </Button>
          )}
          {row.kind === 'added' && removed.length > 0 && (
            <div className="space-y-2 rounded-lg bg-[#f6f1e9] p-3">
              <label className="block text-sm">
                Was this recreated from a removed item?
                <select
                  className="auth-field mt-1 w-full"
                  aria-label="Was this recreated from a removed item?"
                  value={matchId}
                  onChange={(e) => setMatchId(e.target.value)}
                  disabled={busy}
                >
                  <option value="">Choose only if this is a replacement</option>
                  {removed.map((r) => (
                    <option key={r.itemId} value={r.itemId}>
                      {r.previous?.code} · {r.previousItem?.title}
                    </option>
                  ))}
                </select>
              </label>
              <Button
                variant="secondary"
                disabled={busy || !removed.some((r) => r.itemId === matchId)}
                onClick={() => {
                  const old = removed.find((r) => r.itemId === matchId)
                  if (old) match(row, old)
                }}
              >
                Match as replacement
              </Button>
            </div>
          )}
          <label className="block text-sm">
            Review note{needsNote ? ' (required)' : ' (optional)'}
            <textarea
              className="auth-field mt-1 w-full"
              rows={2}
              maxLength={3000}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={busy}
            />
          </label>
          <label className="flex items-start gap-2 text-sm">
            <input
              type="checkbox"
              checked={ack}
              onChange={(e) => setAck(e.target.checked)}
              disabled={busy}
            />
            I reviewed this change, any manual edits and its linked work.
          </label>
          <div className="flex flex-wrap gap-2">
            {invalidDraft ? (
              <Button
                disabled={busy || !ack || !note.trim()}
                onClick={() => apply(row, 'rebuild', note)}
              >
                Prepare a fresh draft
              </Button>
            ) : row.kind === 'removed' ? (
              <>
                <Button
                  disabled={
                    busy ||
                    !canRetire ||
                    row.previous?.status === 'superseded' ||
                    !ack ||
                    (needsNote && !note.trim())
                  }
                  onClick={() => apply(row, 'retire', note)}
                >
                  Confirm retirement
                </Button>
                {!canRetire && (
                  <p className={help}>
                    A project lead with requirement archiving access must
                    confirm retirement.
                  </p>
                )}
                <Button
                  variant="secondary"
                  disabled={
                    busy ||
                    row.previous?.status === 'archived' ||
                    !ack ||
                    !note.trim()
                  }
                  onClick={() => apply(row, 'retain', note)}
                >
                  Retain independently
                </Button>
              </>
            ) : (
              <Button
                disabled={
                  busy ||
                  !row.responsibilityValid ||
                  !ack ||
                  (needsNote && !note.trim())
                }
                onClick={() =>
                  apply(row, restore ? 'restore' : 'activate', note)
                }
              >
                {row.kind === 'unchanged'
                  ? 'Confirm carry forward'
                  : row.previous && !restore
                    ? 'Activate replacement'
                    : restore
                      ? 'Activate as a new requirement'
                      : 'Activate requirement'}
              </Button>
            )}
          </div>
        </div>
      )}
    </article>
  )
}
export default function BriefReconciliation({
  projectId,
  workspaceId,
  revision,
  owners,
}: {
  projectId: string
  workspaceId: string
  revision: BriefRevision
  owners: { id: string; name: string }[]
}) {
  const query = useBriefRequirementChanges(projectId, revision.id),
    qc = useQueryClient(),
    [error, setError] = useState('')
  const mutation = useMutation({
    mutationFn: async ({
      rpc,
      args,
    }: {
      rpc: string
      args: Record<string, unknown>
    }) => {
      const r = await supabase.rpc(rpc, args)
      if (r.error) throw r.error
      return r.data
    },
    onSuccess: async () => {
      setError('')
      invalidateRequirementsLists(qc, workspaceId, projectId)
      await Promise.all([
        qc.invalidateQueries({ queryKey: ['brief-reconciliation'] }),
        qc.invalidateQueries({ queryKey: ['project-brief'] }),
        qc.invalidateQueries({
          predicate: (q) =>
            ['requirement', 'requirement-chain', 'requirement-trace'].includes(
              String(q.queryKey[0]),
            ),
        }),
        qc.invalidateQueries({ queryKey: ['overview-project'] }),
      ])
    },
    onError: (e) => {
      setError(humanizeError(e))
      void query.refetch()
    },
  })
  const run = (rpc: string, args: Record<string, unknown>) =>
      mutation.mutate({
        rpc,
        args: { p_project_id: projectId, p_revision_id: revision.id, ...args },
      }),
    data = query.data
  return (
    <section
      id="brief-reconciliation"
      aria-label="Agreed requirements activation"
      className={panel}
    >
      <h2 className="text-lg font-semibold">Review requirement changes</h2>
      {error && (
        <p role="alert" className="text-sm text-red-700">
          {error}
        </p>
      )}
      {query.isPending ? (
        <p role="status">Checking the requirement handoff…</p>
      ) : query.isError ? (
        <p role="alert">
          Could not load requirement changes.{' '}
          <button className="auth-link" onClick={() => void query.refetch()}>
            Retry requirement changes
          </button>
        </p>
      ) : (
        data && (
          <>
            <p role="status" className="text-sm font-semibold">
              {!data.prepared
                ? 'Agreed · requirement handoff not prepared'
                : data.pending
                  ? `Agreed · ${data.pending} requirement updates pending`
                  : 'Agreed · requirement handoff complete'}
            </p>
            <p className="text-sm text-[#786b60]">
              Keep unchanged requirements, review replacements and additions,
              and explicitly resolve removals. Old requirements remain in force
              until replacements activate. Earlier agreements and design
              evidence stay intact.
            </p>
            {!data.canManage && !data.prepared && (
              <p className={help}>
                A project lead with requirement creation and editing access can
                prepare this handoff. You can view its progress here.
              </p>
            )}
            {data.canManage && data.current && !data.prepared && (
              <Button
                disabled={mutation.isPending}
                onClick={() => run('generate_brief_requirements', {})}
              >
                Create draft requirements
              </Button>
            )}
            {data.prepared && (
              <>
                <p className={help}>
                  {data.rows.every((r) => !r.previous)
                    ? `${revision.generatedCount} drafts generated from this revision.`
                    : `${data.rows.filter((r) => r.kind !== 'removed').length} requirements linked to this revision.`}
                </p>
                {data.rows
                  .filter((r) => r.state === 'pending')
                  .map((row) => (
                    <ChangeRow
                      key={row.itemId}
                      row={row}
                      owners={owners}
                      removed={data.rows.filter(
                        (r) => r.kind === 'removed' && r.state === 'pending',
                      )}
                      canManage={data.canManage && data.current}
                      canRetire={data.canRetire}
                      busy={mutation.isPending || query.isFetching}
                      workspaceId={workspaceId}
                      projectId={projectId}
                      apply={(r, action, note) =>
                        action === 'rebuild'
                          ? run('rebuild_brief_requirement_draft', {
                              p_item_id: r.itemId,
                              p_expected_token: r.token,
                              p_note: note,
                            })
                          : run('apply_brief_requirement_change', {
                              p_item_id: r.itemId,
                              p_expected_token: r.token,
                              p_action: action,
                              p_acknowledge: true,
                              p_note: note,
                            })
                      }
                      unmatch={(r) => {
                        const old = data.rows.find(
                          (o) => o.itemId === r.matchedFrom,
                        )
                        if (old)
                          run('unmatch_brief_requirement_change', {
                            p_new_item_id: r.itemId,
                            p_removed_item_id: old.itemId,
                            p_expected_new_token: r.token,
                            p_expected_removed_token: old.token,
                          })
                      }}
                      match={(r, old) =>
                        run('match_brief_requirement_change', {
                          p_new_item_id: r.itemId,
                          p_removed_item_id: old.itemId,
                          p_expected_new_token: r.token,
                          p_expected_removed_token: old.token,
                        })
                      }
                    />
                  ))}
                <details>
                  <summary className="auth-link cursor-pointer text-sm">
                    Completed decisions (
                    {data.rows.filter((r) => r.state !== 'pending').length})
                  </summary>
                  <div className="mt-3 space-y-3">
                    {data.rows
                      .filter((r) => r.state !== 'pending')
                      .map((row) => (
                        <ChangeRow
                          key={row.itemId}
                          row={row}
                          owners={owners}
                          removed={[]}
                          canManage={false}
                          canRetire={false}
                          busy={false}
                          workspaceId={workspaceId}
                          projectId={projectId}
                          apply={() => {}}
                          match={() => {}}
                          unmatch={() => {}}
                        />
                      ))}
                  </div>
                </details>
                <Link
                  className="auth-link block text-sm"
                  to={`/workspace/${workspaceId}/project/${projectId}/requirements?view=all&status=draft`}
                >
                  Review and activate requirements
                </Link>
              </>
            )}
          </>
        )
      )}
    </section>
  )
}
