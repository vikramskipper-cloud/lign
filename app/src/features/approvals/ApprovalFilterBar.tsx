import { ChevronDown } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import type { ApprovalDashboardView } from './queries'

const VIEW_LABELS: Record<ApprovalDashboardView, string> = {
  awaiting_me: 'Awaiting my decision',
  awaiting_others: 'Awaiting others',
  approved: 'Approved',
  rejected: 'Rejected',
  expired_cancelled: 'Expired / cancelled',
  recent: 'Recent',
  bookmarks: 'Bookmarks',
}

export function ApprovalFilterBar({
  value,
  onChange,
}: {
  value: ApprovalDashboardView
  onChange: (v: ApprovalDashboardView) => void
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
        {(Object.keys(VIEW_LABELS) as ApprovalDashboardView[]).map((k) => (
          <DropdownMenuItem key={k} onSelect={() => onChange(k)}>
            {VIEW_LABELS[k]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
