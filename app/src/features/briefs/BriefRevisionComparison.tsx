import { useState } from 'react'
import type { BriefRevision } from './queries'
import {
  compareBriefPackages,
  earlierRevisions,
  type ReviewPackage,
} from './reviewModel'
export default function BriefRevisionComparison({
  revisions,
  revision,
  current,
  loading,
  error,
  onRetry,
  dirty,
  owners,
}: {
  revisions: BriefRevision[]
  revision?: BriefRevision
  current: ReviewPackage
  loading: boolean
  error: boolean
  onRetry: () => void
  dirty: boolean
  owners: { id: string; name: string }[]
}) {
  const earlier = earlierRevisions(revisions, revision),
    [chosen, setChosen] = useState(''),
    baseline = earlier.find((r) => r.id === chosen) ?? earlier[0]
  if (!baseline) return null
  const changes = compareBriefPackages(
    {
      document: baseline.document,
      files: baseline.attachments,
      references: baseline.document.referenceSelection ?? [],
    },
    current,
    owners,
  )
  return (
    <details
      className="space-y-3 rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5"
      aria-label="Revision comparison"
    >
      <summary className="auth-link cursor-pointer font-semibold">
        Compare revisions
      </summary>
      <div className="space-y-4 pt-2">
        <p className="text-sm">
          Compare{' '}
          {revision
            ? `saved revision ${revision.number}`
            : `the working draft${dirty ? ' (including unsaved edits)' : ''}`}{' '}
          with an earlier saved package. Feedback remains a recorded request;
          this comparison does not mark it resolved.
        </p>
        <label className="block text-sm">
          Compare with
          <select
            className="auth-field mt-1 w-full"
            value={baseline.id}
            onChange={(e) => setChosen(e.target.value)}
          >
            {earlier.map((r) => (
              <option key={r.id} value={r.id}>
                Revision {r.number} ·{' '}
                {r.decision?.decision === 'agreed'
                  ? 'Agreed'
                  : r.decision?.decision === 'changes_requested'
                    ? 'Changes requested'
                    : 'Requested'}
              </option>
            ))}
          </select>
        </label>
        {baseline.decision?.comment && (
          <blockquote className="space-y-1 rounded-lg border border-[#e8c898] bg-[#fff7eb] p-3">
            <p className="text-sm font-semibold">
              Feedback on revision {baseline.number} ·{' '}
              {baseline.decision.actorName}
            </p>
            <p className="whitespace-pre-wrap break-words text-sm">
              {baseline.decision.comment}
            </p>
          </blockquote>
        )}
        {loading ? (
          <p role="status">Loading comparison references…</p>
        ) : error ? (
          <p role="alert">
            Comparison is incomplete because selected references could not be
            loaded.{' '}
            <button className="auth-link" onClick={onRetry}>
              Retry comparison
            </button>
          </p>
        ) : (
          <>
            <p role="status" className="text-sm font-medium">
              {changes.length
                ? `${changes.length} ${changes.length === 1 ? 'change' : 'changes'} from revision ${baseline.number}`
                : 'No content changes from revision ' + baseline.number}
            </p>
            <ul className="space-y-3">
              {changes.map((c, index) => (
                <li
                  key={index}
                  className="space-y-3 rounded-lg border border-[#e5ddd3] bg-white p-4"
                >
                  <p className="text-xs text-[#786b60]">
                    {c.section} · {c.kind}
                  </p>
                  <h3 className="break-words font-semibold">{c.title}</h3>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div>
                      <h4 className="text-xs font-semibold">
                        Before · revision {baseline.number}
                      </h4>
                      <p className="mt-1 whitespace-pre-wrap break-words text-sm">
                        {c.kind === 'Added'
                          ? 'Not included'
                          : c.before || 'Empty'}
                      </p>
                    </div>
                    <div>
                      <h4 className="text-xs font-semibold">
                        After ·{' '}
                        {revision
                          ? `revision ${revision.number}`
                          : 'working draft'}
                      </h4>
                      <p className="mt-1 whitespace-pre-wrap break-words text-sm">
                        {c.kind === 'Removed' ? 'Removed' : c.after || 'Empty'}
                      </p>
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </details>
  )
}
