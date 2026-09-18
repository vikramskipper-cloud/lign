import { ChevronDown } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'

export type CommentFilter = 'all' | 'unresolved' | 'mine' | 'mentions'

const LABELS: Record<CommentFilter, string> = {
  all: 'All',
  unresolved: 'Unresolved',
  mine: 'Mine',
  mentions: '@ Mentions me',
}

export function CommentFilterBar({
  value,
  onChange,
}: {
  value: CommentFilter
  onChange: (v: CommentFilter) => void
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="secondary" size="sm">
          {LABELS[value]}
          <ChevronDown className="ml-1 h-3.5 w-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[10rem]">
        {(Object.keys(LABELS) as CommentFilter[]).map((k) => (
          <DropdownMenuItem key={k} onSelect={() => onChange(k)}>
            {LABELS[k]}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
