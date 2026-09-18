import { useReleaseComparison } from './queries'

interface Props {
  releaseId: string
  compareToId: string | null
}

export function ReleaseComparisonView({ releaseId, compareToId }: Props) {
  const q = useReleaseComparison(releaseId, compareToId)
  if (q.isLoading) {
    return <p className="text-xs text-[--color-text-muted]">Loading comparison…</p>
  }
  if (q.isError || !q.data) {
    return <p className="text-xs text-[--color-danger]">Couldn't load comparison.</p>
  }
  const d = q.data
  if (!d.compare_to) {
    return (
      <p className="text-xs text-[--color-text-muted]">
        No prior release to compare against. Once this release is superseded by
        another, or you pass an explicit comparison target, this tab will render
        the diff.
      </p>
    )
  }
  return (
    <div className="space-y-3 text-xs">
      <div className="rounded-[--radius-sm] border border-[--color-border] p-3">
        <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
          Comparing
        </div>
        <div className="mt-1">
          <span className="font-mono">{d.this_release?.code ?? '—'}</span> vs.{' '}
          <span className="font-mono">{d.compare_to.code ?? '—'}</span>
        </div>
      </div>
      <DiffBlock title="Added" items={d.item_diff.added.map((i) => `${i.design_asset_id.slice(0,8)} v=${i.version_id.slice(0,8)}`)} />
      <DiffBlock title="Removed" items={d.item_diff.removed.map((i) => `${i.design_asset_id.slice(0,8)} v=${i.version_id.slice(0,8)}`)} />
      <DiffBlock
        title="Version changed"
        items={d.item_diff.changed_version.map(
          (i) =>
            `${i.design_asset_id.slice(0, 8)}: ${i.compare_version_id.slice(0, 8)} → ${i.this_version_id.slice(0, 8)}`,
        )}
      />
    </div>
  )
}

function DiffBlock({ title, items }: { title: string; items: string[] }) {
  return (
    <div className="rounded-[--radius-sm] border border-[--color-border] p-3">
      <div className="mb-1 text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        {title}
      </div>
      {items.length === 0 ? (
        <p className="text-[--color-text-muted]">—</p>
      ) : (
        <ul className="space-y-1 font-mono">
          {items.map((s) => (
            <li key={s}>{s}</li>
          ))}
        </ul>
      )}
    </div>
  )
}
