import { ChevronDown } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import type { DashboardView } from './queries'

const VIEW_LABELS: Record<DashboardView, string> = {
  assigned_to_me: 'Assigned to me',
  waiting_on_others: 'Waiting on others',
  overdue: 'Overdue',
  completed: 'Completed',
  recent: 'Recent',
  bookmarks: 'Bookmarks',
}

export function ReviewFilterBar({
  value,
  onChange,
}: {
  value: DashboardView
  onChange: (v: DashboardView) => void
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="secondary" size="sm">
          {VIEW_LABELS[value]}
          <ChevronDown className="ml-1 h-3.5 w-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[12rem]">
        {(Object.keys(VIEW_LABELS) as DashboardView[]).map((k) => (
          <DropdownMenuItem key={k} onSelect={() => onChange(k)}>
            {VIEW_LABELS[k]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
