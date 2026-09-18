import { Link } from 'react-router'
import { Card } from '@/ui/card'
import { StatusBadge } from '@/features/shared/StatusBadge'
import { DisciplineChip } from '@/features/disciplines/DisciplineChip'
import { AssetCardThumb } from '@/features/files/AssetCardThumb'
import { relative, absolute } from '@/lib/formatDate'
import { cn } from '@/lib/cn'
import type { AssetRow } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  asset: AssetRow
  /** Name of the asset's discipline, if any. */
  disciplineName: string | undefined
  /** Sequence number of the current version, if any. */
  currentVersionSequence: number | undefined
  /** Hide the discipline chip when a discipline filter is active (chip is redundant). */
  hideDisciplineChip?: boolean
  scopeQuery?: string
}

/**
 * Grid tile for one DesignAsset.
 *
 * Layout uses CSS grid with a reserved 24×24 slot in the top-right for a
 * future Favorite/Star indicator (APP 003 architecture §3.3). The slot is
 * empty (aria-hidden) so the card cannot reflow when Favorites lands.
 */
export function AssetCard({
  workspaceId,
  projectId,
  asset,
  disciplineName,
  currentVersionSequence,
  hideDisciplineChip,
  scopeQuery,
}: Props) {
  const href = `/workspace/${workspaceId}/project/${projectId}/asset/${asset.id}${
    scopeQuery ? `?${scopeQuery}` : ''
  }`
  return (
    <Card className="p-4 transition-colors hover:border-[--color-border-strong]">
      <Link
        to={href}
        className={cn(
          'grid gap-2 outline-none',
          '[grid-template-columns:1fr_24px] [grid-template-areas:"name_fav""meta_meta""thumb_thumb"]',
        )}
      >
        <div className="[grid-area:name] flex items-center gap-2 min-w-0">
          <span className="truncate text-sm font-semibold text-[--color-text]">{asset.name}</span>
        </div>
        {/* Reserved slot for future Favorite indicator (APP 003 §3.3). */}
        <span
          aria-hidden="true"
          className="asset-card__favorite-slot [grid-area:fav] h-6 w-6"
        />
        <div className="[grid-area:meta] flex flex-wrap items-center gap-1.5 text-xs text-[--color-text-subtle]">
          {!hideDisciplineChip && disciplineName && <DisciplineChip name={disciplineName} />}
          {currentVersionSequence != null && (
            <span className="rounded-[--radius-sm] bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] text-[--color-text-muted]">
              v{currentVersionSequence}
            </span>
          )}
          {asset.status !== 'active' && <StatusBadge status={asset.status} />}
          {asset.code && <span className="font-mono">{asset.code}</span>}
          <span aria-hidden>·</span>
          <span title={absolute(asset.updated_at)}>updated {relative(asset.updated_at)}</span>
        </div>
        <div className="[grid-area:thumb] mt-1 h-24 overflow-hidden rounded-[--radius-md]">
          <AssetCardThumb currentVersionId={asset.current_version_id} />
        </div>
      </Link>
    </Card>
  )
}
