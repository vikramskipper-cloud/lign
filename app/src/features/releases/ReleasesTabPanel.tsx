import { Link } from 'react-router'
import { Package } from 'lucide-react'
import { useReleasesForAsset, useReleasesForVersion } from './queries'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative, absolute } from '@/lib/formatDate'

interface Props {
  workspaceId: string
  projectId: string
  designAssetId: string
  versionId: string | null
  /** Scope: 'asset' returns every release that includes any version of this asset;
   *  'version' scopes to the specific version. Freeze Index §12. */
  scope?: 'asset' | 'version'
}

/**
 * RightPanel tab for the Design Workspace — lists releases that include the
 * current asset (or version). Read-only.
 */
export function ReleasesTabPanel({
  workspaceId,
  projectId,
  designAssetId,
  versionId,
  scope = 'version',
}: Props) {
  const assetQ = useReleasesForAsset(scope === 'asset' ? designAssetId : undefined)
  const versionQ = useReleasesForVersion(
    scope === 'version' && versionId ? versionId : undefined,
  )
  const q = scope === 'asset' ? assetQ : versionQ
  const rows = q.data ?? []

  if (q.isLoading) {
    return <p className="p-3 text-xs text-[--color-text-muted]">Loading…</p>
  }
  if (q.isError) {
    return <p className="p-3 text-xs text-[--color-danger]">Couldn't load.</p>
  }
  if (rows.length === 0) {
    return (
      <div className="p-3 text-xs text-[--color-text-muted]">
        <Package className="mb-1 h-4 w-4" />
        No releases include this {scope}.
      </div>
    )
  }
  return (
    <ul className="space-y-1 p-2">
      {rows.map((r) => (
        <li key={r.out_release_id}>
          <Link
            to={`/workspace/${workspaceId}/project/${projectId}/release/${r.out_release_id}`}
            className="flex items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-xs hover:bg-[--color-surface-2]"
          >
            {r.out_code && (
              <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] uppercase text-[--color-text-muted]">
                {r.out_code}
              </span>
            )}
            <span className="min-w-0 flex-1 truncate">{r.out_name}</span>
            <StateBadge state={r.out_status as WorkflowState} />
            {r.out_released_at && (
              <span
                className="text-[10px] text-[--color-text-subtle]"
                title={absolute(r.out_released_at)}
              >
                {relative(r.out_released_at)}
              </span>
            )}
          </Link>
        </li>
      ))}
    </ul>
  )
}
