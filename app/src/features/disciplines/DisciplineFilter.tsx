import { ChevronDown, Settings2 } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { useDisciplines } from './queries'
import { DisciplineManagerPopover } from './DisciplineManagerPopover'

interface Props {
  workspaceId: string
  projectId: string
  value: string | null
  onChange: (value: string | null) => void
  canEdit: boolean
  assetCounts?: Record<string, number>
}

export function DisciplineFilter({
  workspaceId,
  projectId,
  value,
  onChange,
  canEdit,
  assetCounts,
}: Props) {
  const { data } = useDisciplines(projectId)
  const items = data ?? []
  const selected = items.find((d) => d.id === value)

  return (
    <div className="flex items-center gap-1">
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="secondary" size="sm">
            <span className="mr-1 text-[--color-text-muted]">Discipline:</span>
            {selected ? selected.name : 'All'}
            <ChevronDown className="ml-1 h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="min-w-[12rem]">
          <DropdownMenuItem onSelect={() => onChange(null)}>All disciplines</DropdownMenuItem>
          {items.length > 0 && <DropdownMenuSeparator />}
          {items.map((d) => (
            <DropdownMenuItem key={d.id} onSelect={() => onChange(d.id)}>
              {d.name}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>

      <DisciplineManagerPopover
        workspaceId={workspaceId}
        projectId={projectId}
        canEdit={canEdit}
        assetCounts={assetCounts}
        trigger={
          <Button
            variant="ghost"
            size="icon"
            aria-label="Manage disciplines"
            title="Manage disciplines"
          >
            <Settings2 className="h-4 w-4" />
          </Button>
        }
      />
    </div>
  )
}
