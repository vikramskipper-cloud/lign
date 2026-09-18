import { ChevronDown } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import type { RequirementsDashboardView } from './queries'

const VIEW_LABELS: Record<RequirementsDashboardView, string> = {
  all_active: 'All active',
  assigned_to_me: 'Assigned to me',
  recently_updated: 'Recently updated',
  by_status: 'By status',
  by_priority: 'By priority',
  by_source: 'By source',
  needs_assessment: 'Needs assessment',
  overdue_critical: 'Overdue critical',
  bookmarks: 'Bookmarks',
  archived: 'Archived',
  superseded: 'Superseded',
  compliance: 'Compliance',
  all: 'All (incl. terminal)',
}

/** APP 008 dashboard view picker. Mirrors ApprovalFilterBar shape. */
export function RequirementFilterBar({
  value,
  onChange,
}: {
  value: RequirementsDashboardView
  onChange: (v: RequirementsDashboardView) => void
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="secondary" size="sm">
          {VIEW_LABELS[value]}
          <ChevronDown className="ml-1 h-3.5 w-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[14rem]">
        {(Object.keys(VIEW_LABELS) as RequirementsDashboardView[]).map((k) => (
          <DropdownMenuItem key={k} onSelect={() => onChange(k)}>
            {VIEW_LABELS[k]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
