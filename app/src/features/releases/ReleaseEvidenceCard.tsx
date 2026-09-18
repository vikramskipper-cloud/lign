import { useReleaseEvidence } from './queries'

interface Props {
  releaseId: string
}

/**
 * Renders the frozen evidence_snapshot (immutable once released) alongside a
 * live_delta comparison. When the snapshot is NULL (release still draft), only
 * the live re-computation is shown per Freeze Index §5.4 fallback rendering.
 */
export function ReleaseEvidenceCard({ releaseId }: Props) {
  const q = useReleaseEvidence(releaseId)
  if (q.isLoading) {
    return <p className="text-xs text-[--color-text-muted]">Loading evidence…</p>
  }
  if (q.isError || !q.data) {
    return (
      <p className="text-xs text-[--color-danger]">Couldn't load evidence.</p>
    )
  }
  const snapshot = q.data.snapshot as
    | { items?: Array<Record<string, unknown>>; captured_at?: string; approval_request_ids?: string[] }
    | null
  const live = q.data.live_delta

  return (
    <div className="space-y-4">
      <div className="rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] p-3 text-xs">
        <div className="mb-2 flex items-center justify-between">
          <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
            Evidence snapshot
          </div>
          <div className="text-[10px] text-[--color-text-subtle]">
            {snapshot?.captured_at ? `captured ${snapshot.captured_at}` : 'not yet captured (live view)'}
          </div>
        </div>
        {snapshot?.items && snapshot.items.length > 0 ? (
          <ul className="space-y-1">
            {snapshot.items.map((it, idx) => (
              <li
                key={idx}
                className="rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface-2] p-2"
              >
                <div className="font-mono text-[10px] text-[--color-text-muted]">
                  {(it.design_asset_name as string) ?? (it.design_asset_id as string).slice(0, 8)} · v
                  {String(it.version_sequence ?? '?')}
                </div>
                <div className="text-[--color-text]">
                  approval: {(it.approval_outcome as { status?: string } | null)?.status ?? '—'} · reviews:{' '}
                  {String(it.completed_review_count ?? 0)}
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-[--color-text-subtle]">
            Snapshot is empty; evidence will be captured atomically at publish.
          </p>
        )}
      </div>
      <div className="rounded-[--radius-sm] border border-dashed border-[--color-border] p-3 text-xs">
        <div className="mb-1 text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
          Live delta ({live.items.length} item{live.items.length === 1 ? '' : 's'})
        </div>
        <p className="text-[--color-text-muted]">
          Live re-computation of approval + requirement readiness. If the release
          is released and the snapshot's values differ from live, an audit trail
          discrepancy has been introduced upstream (frozen evidence remains
          authoritative).
        </p>
      </div>
    </div>
  )
}
