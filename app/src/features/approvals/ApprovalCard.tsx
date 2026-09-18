import { Link } from 'react-router'
import { Clock, ShieldCheck, Users } from 'lucide-react'
import { Card } from '@/ui/card'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative, absolute } from '@/lib/formatDate'
import { cn } from '@/lib/cn'
import type { ApprovalDashboardRow } from './queries'

const stateFromApproval = (status: ApprovalDashboardRow['out_status']): WorkflowState => {
  switch (status) {
    case 'draft':
      return 'draft'
    case 'pending':
      return 'pending'
    case 'in_progress':
      return 'in_progress'
    case 'approved':
      return 'approved'
    case 'rejected':
      return 'rejected'
    case 'expired':
      return 'expired'
    case 'cancelled':
      return 'cancelled'
    case 'superseded':
      return 'superseded'
  }
}

interface Props {
  row: ApprovalDashboardRow
}

export function ApprovalCard({ row }: Props) {
  const total = row.out_total_approver_count
  const responded = row.out_approved_count + row.out_rejected_count + row.out_abstained_count
  const url = `/workspace/${row.out_workspace_id}/project/${row.out_project_id}/approval/${row.out_id}`
  return (
    <Card className="p-4 transition-colors hover:border-[--color-border-strong]">
      <Link to={url} className="flex flex-col gap-2 outline-none">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0 space-y-0.5">
            <div className="flex items-center gap-2">
              <span className="truncate text-sm font-semibold text-[--color-text]">
                {row.out_title ?? 'Untitled approval'}
              </span>
              {row.out_has_veto_approver && (
                <span
                  title="Veto approver assigned"
                  className="inline-flex items-center gap-0.5 rounded bg-[--color-warning]/15 px-1.5 py-0.5 text-[10px] font-medium text-[--color-warning]"
                >
                  <ShieldCheck className="h-3 w-3" /> Veto
                </span>
              )}
            </div>
            {row.out_description && (
              <p className="line-clamp-1 text-xs text-[--color-text-muted]">
                {row.out_description}
              </p>
            )}
          </div>
          <StateBadge state={stateFromApproval(row.out_status)} />
        </div>

        <div className="flex flex-wrap items-center gap-3 text-xs text-[--color-text-subtle]">
          <span className="inline-flex items-center gap-1">
            <Users className="h-3.5 w-3.5" />
            {responded} / {total}
          </span>
          {row.out_expires_at && (
            <span
              className={cn(
                'inline-flex items-center gap-1',
                row.out_overdue_flag && 'text-[--color-danger]',
              )}
              title={absolute(row.out_expires_at)}
            >
              <Clock className="h-3.5 w-3.5" />
              {row.out_overdue_flag ? 'Expired' : `expires ${relative(row.out_expires_at)}`}
            </span>
          )}
          <span className="uppercase tracking-wide">{row.out_policy}</span>
          <span aria-hidden>·</span>
          <span title={absolute(row.out_updated_at)}>
            updated {relative(row.out_updated_at)}
          </span>
        </div>
      </Link>
    </Card>
  )
}
