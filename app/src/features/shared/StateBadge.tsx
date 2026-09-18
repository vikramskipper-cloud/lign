import { cn } from '@/lib/cn'

/**
 * Workflow-state pill (distinct from lifecycle StatusBadge). Reads generic
 * --color-state-* tokens; extended by Reviews / Changes / Requirements as
 * those slices land.
 */
export type WorkflowState =
  | 'open'
  | 'resolved'
  | 'in_progress'
  | 'waiting'
  | 'ready_for_review'
  | 'draft'
  | 'completed'
  | 'cancelled'
  // APP 007 additive
  | 'pending'
  | 'approved'
  | 'rejected'
  | 'expired'
  | 'superseded'
  // APP 008 additive
  | 'active'
  | 'archived'

interface Props {
  state: WorkflowState
  className?: string
  label?: string
}

const LABELS: Record<WorkflowState, string> = {
  open: 'Open',
  resolved: 'Resolved',
  in_progress: 'In progress',
  waiting: 'Waiting',
  ready_for_review: 'Ready for review',
  draft: 'Draft',
  completed: 'Completed',
  cancelled: 'Cancelled',
  pending: 'Pending',
  approved: 'Approved',
  rejected: 'Rejected',
  expired: 'Expired',
  superseded: 'Superseded',
  active: 'Active',
  archived: 'Archived',
}

/**
 * Color mapping. Uses generic --color-state-* tokens where defined;
 * ready/draft use neutral tokens (no dedicated state token defined yet);
 * in_progress/waiting fall back to open+warning-like styling using
 * existing tokens (no new tokens introduced by APP 006).
 */
const STYLES: Record<WorkflowState, string> = {
  open:
    'text-[--color-state-open] bg-[--color-state-open-bg] border border-[--color-state-open]/30',
  resolved:
    'text-[--color-state-resolved] bg-[--color-state-resolved-bg] border border-[--color-state-resolved]/30',
  in_progress:
    'text-[--color-state-open] bg-[--color-state-open-bg] border border-[--color-state-open]/30',
  waiting:
    'text-[--color-warning] bg-[--color-warning]/15 border border-[--color-warning]/30',
  ready_for_review:
    'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]',
  draft:
    'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]',
  completed:
    'text-[--color-state-resolved] bg-[--color-state-resolved-bg] border border-[--color-state-resolved]/30',
  cancelled:
    'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]',
  pending:
    'text-[--color-state-open] bg-[--color-state-open-bg] border border-[--color-state-open]/30',
  approved:
    'text-[--color-state-resolved] bg-[--color-state-resolved-bg] border border-[--color-state-resolved]/30',
  rejected:
    'text-[--color-danger] bg-[--color-danger]/10 border border-[--color-danger]/30',
  expired:
    'text-[--color-warning] bg-[--color-warning]/15 border border-[--color-warning]/30',
  superseded:
    'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]',
  active:
    'text-[--color-state-open] bg-[--color-state-open-bg] border border-[--color-state-open]/30',
  archived:
    'text-[--color-text-muted] bg-[--color-surface-2] border border-[--color-border]',
}

export function StateBadge({ state, className, label }: Props) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium',
        STYLES[state],
        className,
      )}
      aria-label={`${LABELS[state]} state`}
    >
      {label ?? LABELS[state]}
    </span>
  )
}
