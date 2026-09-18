import { Link } from 'react-router'
import { Clock, ListChecks } from 'lucide-react'
import { Card } from '@/ui/card'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { PriorityBadge } from './PriorityBadge'
import { ScopeChip } from './ScopeChip'
import { relative, absolute } from '@/lib/formatDate'
import { cn } from '@/lib/cn'
import type { RequirementDashboardRow } from './queries'

interface Props {
  row: RequirementDashboardRow
}

const stateFromStatus = (
  status: RequirementDashboardRow['status'],
): WorkflowState => status as WorkflowState

export function RequirementCard({ row }: Props) {
  const url = `/workspace/${row.workspace_id}/project/${row.project_id}/requirement/${row.requirement_id}`
  const isOverdue = row.due_at ? new Date(row.due_at) < new Date() : false
  const coverage = row.assessment_coverage
  const totalApplicable = coverage?.applicable_versions_count ?? 0
  const satisfied = coverage?.satisfied_count ?? 0
  return (
    <Card className="p-4 transition-colors hover:border-[--color-border-strong]">
      <Link to={url} className="flex flex-col gap-2 outline-none">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 space-y-0.5">
            <div className="flex items-center gap-2">
              <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] uppercase text-[--color-text-muted]">
                {row.code}
              </span>
              <span className="truncate text-sm font-semibold text-[--color-text]">
                {row.title}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-1.5 pt-1">
              {row.category_kind && <ScopeChip label={row.category_kind} />}
              {row.source_kind && <ScopeChip label={row.source_kind} />}
              <ScopeChip
                label={
                  row.applicability_summary?.scope === 'project_wide'
                    ? 'Project-wide'
                    : `${row.applicability_summary?.asset_count ?? 0} asset${
                        (row.applicability_summary?.asset_count ?? 0) === 1
                          ? ''
                          : 's'
                      }`
                }
                tone="muted"
              />
            </div>
          </div>
          <div className="flex flex-col items-end gap-1">
            <div className="flex items-center gap-1">
              <PriorityBadge priority={row.priority} />
              <StateBadge state={stateFromStatus(row.status)} />
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-3 text-xs text-[--color-text-subtle]">
          <span className="inline-flex items-center gap-1">
            <ListChecks className="h-3.5 w-3.5" />
            {satisfied} / {totalApplicable} satisfied
          </span>
          {row.due_at && (
            <span
              className={cn(
                'inline-flex items-center gap-1',
                isOverdue && 'text-[--color-danger]',
              )}
              title={absolute(row.due_at)}
            >
              <Clock className="h-3.5 w-3.5" />
              {isOverdue ? 'Overdue' : `due ${relative(row.due_at)}`}
            </span>
          )}
          <span aria-hidden>·</span>
          <span title={absolute(row.updated_at)}>
            updated {relative(row.updated_at)}
          </span>
          {row.project_name && (
            <>
              <span aria-hidden>·</span>
              <span className="truncate">{row.project_name}</span>
            </>
          )}
        </div>
      </Link>
    </Card>
  )
}
