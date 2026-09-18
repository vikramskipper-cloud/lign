import { Button } from '@/ui/button'
import { cn } from '@/lib/cn'
import type {
  InboxFilters,
  NotificationCategory,
  NotificationPriority,
  SourceModule,
} from './types'

interface Props {
  filters: InboxFilters
  onChange: (next: InboxFilters) => void
}

const CATEGORIES: NotificationCategory[] = [
  'assigned_to_me',
  'mentions',
  'project_activity',
  'governance_state_change',
  'deadlines',
  'system',
]

const PRIORITIES: NotificationPriority[] = [
  'critical',
  'high',
  'medium',
  'low',
  'informational',
]

const SOURCES: SourceModule[] = [
  'review',
  'approval',
  'requirement',
  'release',
  'comment',
  'change',
  'annotation',
  'project',
  'workspace',
  'stakeholder',
  'invitation',
]

function toggle<T>(arr: T[] | undefined, v: T): T[] | undefined {
  const set = new Set(arr ?? [])
  if (set.has(v)) set.delete(v)
  else set.add(v)
  const next = Array.from(set)
  return next.length === 0 ? undefined : next
}

/**
 * APP 010 §12.3 / §16.1: Inbox filter chips for category / priority / source
 * plus date-range inputs. Compose with AND semantics between filter families.
 */
export function NotificationFilterBar({ filters, onChange }: Props) {
  const chipCls = (active: boolean) =>
    cn(
      'inline-flex items-center rounded-full border border-[--color-border] px-2.5 py-0.5 text-xs transition-colors',
      active
        ? 'bg-[--color-brand] text-[--color-brand-fg]'
        : 'bg-[--color-surface] text-[--color-text-muted] hover:text-[--color-text]',
    )

  return (
    <div className="flex flex-col gap-2 border-b border-[--color-border] bg-[--color-surface] p-2">
      <div className="flex flex-wrap gap-1">
        <span className="mr-1 self-center text-[0.6875rem] uppercase text-[--color-text-muted]">
          Category
        </span>
        {CATEGORIES.map((c) => {
          const active = filters.category?.includes(c) ?? false
          return (
            <button
              key={c}
              type="button"
              className={chipCls(active)}
              onClick={() =>
                onChange({ ...filters, category: toggle(filters.category, c), cursor: null })
              }
            >
              {c.replace(/_/g, ' ')}
            </button>
          )
        })}
      </div>
      <div className="flex flex-wrap gap-1">
        <span className="mr-1 self-center text-[0.6875rem] uppercase text-[--color-text-muted]">
          Priority
        </span>
        {PRIORITIES.map((p) => {
          const active = filters.priority?.includes(p) ?? false
          return (
            <button
              key={p}
              type="button"
              className={chipCls(active)}
              onClick={() =>
                onChange({ ...filters, priority: toggle(filters.priority, p), cursor: null })
              }
            >
              {p}
            </button>
          )
        })}
      </div>
      <div className="flex flex-wrap gap-1">
        <span className="mr-1 self-center text-[0.6875rem] uppercase text-[--color-text-muted]">
          Source
        </span>
        {SOURCES.map((s) => {
          const active = filters.source?.includes(s) ?? false
          return (
            <button
              key={s}
              type="button"
              className={chipCls(active)}
              onClick={() =>
                onChange({ ...filters, source: toggle(filters.source, s), cursor: null })
              }
            >
              {s}
            </button>
          )
        })}
      </div>
      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-0.5 text-[0.6875rem] uppercase text-[--color-text-muted]">
          From
          <input
            type="date"
            value={filters.dateFrom ?? ''}
            onChange={(e) =>
              onChange({ ...filters, dateFrom: e.target.value || null, cursor: null })
            }
            className="rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1 text-xs text-[--color-text]"
          />
        </label>
        <label className="flex flex-col gap-0.5 text-[0.6875rem] uppercase text-[--color-text-muted]">
          To
          <input
            type="date"
            value={filters.dateTo ?? ''}
            onChange={(e) =>
              onChange({ ...filters, dateTo: e.target.value || null, cursor: null })
            }
            className="rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1 text-xs text-[--color-text]"
          />
        </label>
        <div className="ml-auto">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => onChange({ cursor: null })}
            disabled={
              (filters.category?.length ?? 0) === 0 &&
              (filters.priority?.length ?? 0) === 0 &&
              (filters.source?.length ?? 0) === 0 &&
              !filters.dateFrom &&
              !filters.dateTo
            }
          >
            Clear filters
          </Button>
        </div>
      </div>
    </div>
  )
}
