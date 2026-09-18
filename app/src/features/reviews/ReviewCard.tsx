import { Link } from 'react-router'
import { Clock, MessageSquare, Users } from 'lucide-react'
import { Card } from '@/ui/card'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative, absolute } from '@/lib/formatDate'
import { cn } from '@/lib/cn'
import type { ReviewDashboardRow } from './queries'

const stateFromReview = (status: ReviewDashboardRow['out_status']): WorkflowState => {
  switch (status) {
    case 'draft':
      return 'draft'
    case 'ready_for_review':
      return 'ready_for_review'
    case 'open':
      return 'open'
    case 'in_progress':
      return 'in_progress'
    case 'waiting':
      return 'waiting'
    case 'completed':
      return 'completed'
    case 'cancelled':
      return 'cancelled'
  }
}

interface Props {
  row: ReviewDashboardRow
}

export function ReviewCard({ row }: Props) {
  const total = row.out_total_reviewer_count
  const responded = total - row.out_open_reviewer_count
  const url = `/workspace/${row.out_workspace_id}/project/${row.out_project_id}/review/${row.out_id}`
  return (
    <Card className="p-4 transition-colors hover:border-[--color-border-strong]">
      <Link to={url} className="flex flex-col gap-2 outline-none">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 space-y-0.5">
            <div className="flex items-center gap-2">
              <span className="truncate text-sm font-semibold text-[--color-text]">
                {row.out_title}
              </span>
              <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] text-[--color-text-muted]">
                R{row.out_round_number}
              </span>
            </div>
            {row.out_description && (
              <p className="line-clamp-1 text-xs text-[--color-text-muted]">
                {row.out_description}
              </p>
            )}
          </div>
          <StateBadge state={stateFromReview(row.out_status)} />
        </div>

        <div className="flex flex-wrap items-center gap-3 text-xs text-[--color-text-subtle]">
          <span className="inline-flex items-center gap-1">
            <Users className="h-3.5 w-3.5" />
            {responded} / {total}
          </span>
          {row.out_open_comment_count > 0 && (
            <span className="inline-flex items-center gap-1">
              <MessageSquare className="h-3.5 w-3.5" />
              {row.out_open_comment_count} open
            </span>
          )}
          {row.out_due_at && (
            <span
              className={cn(
                'inline-flex items-center gap-1',
                row.out_overdue_flag && 'text-[--color-danger]',
              )}
              title={absolute(row.out_due_at)}
            >
              <Clock className="h-3.5 w-3.5" />
              {row.out_overdue_flag ? 'Overdue' : `due ${relative(row.out_due_at)}`}
            </span>
          )}
          {row.out_policy !== 'parallel' && (
            <span className="uppercase tracking-wide">{row.out_policy}</span>
          )}
          <span aria-hidden>·</span>
          <span title={absolute(row.out_updated_at)}>
            updated {relative(row.out_updated_at)}
          </span>
        </div>
      </Link>
    </Card>
  )
}
