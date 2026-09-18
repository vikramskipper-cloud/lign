import { useReleaseActivity } from './queries'
import { relative, absolute } from '@/lib/formatDate'

export function ReleaseHistoryList({ releaseId }: { releaseId: string }) {
  const q = useReleaseActivity(releaseId)
  if (q.isLoading) {
    return <p className="text-xs text-[--color-text-muted]">Loading…</p>
  }
  if (q.isError) {
    return <p className="text-xs text-[--color-danger]">Couldn't load history.</p>
  }
  const rows = q.data ?? []
  if (rows.length === 0) {
    return <p className="text-xs text-[--color-text-muted]">No activity yet.</p>
  }
  return (
    <ul className="space-y-1">
      {rows.map((e) => (
        <li
          key={e.out_id}
          className="rounded-[--radius-sm] border border-[--color-border] px-2 py-1.5 text-xs"
        >
          <div className="font-medium">{e.out_event_type}</div>
          {e.out_subject_label && (
            <div className="truncate text-[--color-text-muted]">
              {e.out_subject_label}
            </div>
          )}
          <div
            className="text-[10px] text-[--color-text-subtle]"
            title={absolute(e.out_occurred_at)}
          >
            {relative(e.out_occurred_at)}
          </div>
        </li>
      ))}
    </ul>
  )
}
