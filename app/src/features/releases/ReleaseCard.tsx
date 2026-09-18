import { Link } from 'react-router'
import { Package, Clock } from 'lucide-react'
import { Card } from '@/ui/card'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative, absolute } from '@/lib/formatDate'
import type { ReleaseDashboardRow } from './queries'

const stateFromStatus = (s: string): WorkflowState => s as WorkflowState

export function ReleaseCard({ row }: { row: ReleaseDashboardRow }) {
  const url = `/workspace/${row.out_workspace_id}/project/${row.out_project_id}/release/${row.out_release_id}`
  const primaryDate =
    row.out_released_at ?? row.out_withdrawn_at ?? row.out_updated_at
  return (
    <Card className="p-4 transition-colors hover:border-[--color-border-strong]">
      <Link to={url} className="flex flex-col gap-2 outline-none">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 space-y-0.5">
            <div className="flex items-center gap-2">
              {row.out_code && (
                <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] uppercase text-[--color-text-muted]">
                  {row.out_code}
                </span>
              )}
              <span className="truncate text-sm font-semibold text-[--color-text]">
                {row.out_name}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-1.5 pt-1 text-[11px] text-[--color-text-muted]">
              {row.out_release_type && (
                <span className="rounded-full bg-[--color-surface-2] px-2 py-0.5 uppercase tracking-wide">
                  {row.out_release_type}
                </span>
              )}
              {row.out_channel && (
                <span className="truncate">
                  {row.out_channel}
                </span>
              )}
              <span className="inline-flex items-center gap-1">
                <Package className="h-3 w-3" />
                {row.out_item_count} item{row.out_item_count === 1 ? '' : 's'}
              </span>
            </div>
          </div>
          <div className="flex flex-col items-end gap-1">
            <StateBadge state={stateFromStatus(row.out_status)} />
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-3 text-xs text-[--color-text-subtle]">
          {primaryDate && (
            <span className="inline-flex items-center gap-1" title={absolute(primaryDate)}>
              <Clock className="h-3.5 w-3.5" />
              {row.out_status === 'released'
                ? `released ${relative(primaryDate)}`
                : row.out_status === 'withdrawn'
                  ? `withdrawn ${relative(primaryDate)}`
                  : `updated ${relative(primaryDate)}`}
            </span>
          )}
          {row.out_project_name && (
            <>
              <span aria-hidden>·</span>
              <span className="truncate">{row.out_project_name}</span>
            </>
          )}
        </div>
      </Link>
    </Card>
  )
}
