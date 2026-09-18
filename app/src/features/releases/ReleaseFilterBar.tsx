import { ChevronDown } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import type { ReleasesDashboardView } from './queries'

const VIEW_LABELS: Record<ReleasesDashboardView, string> = {
  all: 'All',
  draft: 'Drafts',
  released: 'Released',
  withdrawn: 'Withdrawn',
  discarded: 'Discarded',
  published_by_me: 'Published by me',
}

export function ReleaseFilterBar({
  value,
  onChange,
}: {
  value: ReleasesDashboardView
  onChange: (v: ReleasesDashboardView) => void
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
        {(Object.keys(VIEW_LABELS) as ReleasesDashboardView[]).map((k) => (
          <DropdownMenuItem key={k} onSelect={() => onChange(k)}>
            {VIEW_LABELS[k]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
