import { Link } from 'react-router'
import { Star } from 'lucide-react'
import { StatusBadge } from '@/features/shared/StatusBadge'
import { EmptyState } from '@/ui/empty-state'
import { relative, absolute } from '@/lib/formatDate'
import { cn } from '@/lib/cn'
import type { AssetVersionRow } from '../queries'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  versions: AssetVersionRow[]
  activeVersionId: string | null
  currentVersionId: string | null
  scopeQuery?: string
}

export function VersionsPanel({
  workspaceId,
  projectId,
  assetId,
  versions,
  activeVersionId,
  currentVersionId,
  scopeQuery,
}: Props) {
  if (versions.length === 0) {
    return (
      <EmptyState
        title="No versions yet"
        description="Version uploads land in APP 004."
        className="mx-3 mt-3"
      />
    )
  }
  const suffix = scopeQuery ? `?${scopeQuery}` : ''
  return (
    <ul className="space-y-1 p-3">
      {versions.map((v) => {
        const isActive = v.id === activeVersionId
        const isCurrent = v.id === currentVersionId
        return (
          <li key={v.id}>
            <Link
              to={`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${v.id}${suffix}`}
              className={cn(
                'block rounded-[--radius-sm] border border-transparent px-2 py-1.5 text-sm hover:bg-[--color-surface-2]',
                isActive && 'border-[--color-border-strong] bg-[--color-surface-2]',
              )}
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                  <span className="font-mono text-xs text-[--color-text-muted]">v{v.sequence}</span>
                  {v.label && <span className="truncate">{v.label}</span>}
                  {isCurrent && (
                    <span className="inline-flex items-center gap-0.5 text-[10px] text-[--color-text-muted]">
                      <Star className="h-3 w-3" />
                      current
                    </span>
                  )}
                </div>
                <StatusBadge status={v.status} />
              </div>
              <div className="mt-0.5 flex items-center gap-2 text-[11px] text-[--color-text-subtle]">
                {v.published_at ? (
                  <span title={absolute(v.published_at)}>
                    published {relative(v.published_at)}
                  </span>
                ) : (
                  <span>Draft — no files yet</span>
                )}
                {v.deprecation_note && <span>· {v.deprecation_note}</span>}
              </div>
            </Link>
          </li>
        )
      })}
    </ul>
  )
}
