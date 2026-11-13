import { useNavigate } from 'react-router'
import { Check, ChevronDown } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { useProjects } from '@/shell/queries'
import {usePinnedProjectIds} from '@/features/home/pins'
import { Skeleton } from '@/ui/skeleton'

interface Props {
  workspaceId: string
  currentProjectId: string
  currentName?: string
  iconOnly?: boolean
}

/**
 * The project name in the breadcrumb doubles as a dropdown switcher. Per
 * APP 002 §7 we do NOT ship a separate project switcher widget — this is it.
 */
export function ProjectBreadcrumbSwitcher({ workspaceId, currentProjectId, currentName, iconOnly=false }: Props) {
  const { data, isLoading } = useProjects(workspaceId)
  const navigate = useNavigate()
  const pins=usePinnedProjectIds(workspaceId)
  const ordered=[...(data??[])].sort((a,b)=>Number(Boolean(pins.data?.includes(b.id)))-Number(Boolean(pins.data?.includes(a.id))))

  if (isLoading) return <Skeleton className={iconOnly?'h-7 w-7':'h-6 w-32'} />

  const switchTo = (projectId: string) => {
    navigate(`/workspace/${workspaceId}/project/${projectId}/overview`)
  }

  const others = (data ?? []).filter((p) => p.id !== currentProjectId)

  if (!currentName && others.length === 0) return null

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button aria-label="Switch project" variant="ghost" size="sm" className={iconOnly?'h-7 w-7 p-0':'h-7 gap-1 px-1.5 text-sm font-medium'}>
          {!iconOnly&&<span className="max-w-[16rem] truncate">{currentName ?? 'Project'}</span>}
          <ChevronDown className="h-3.5 w-3.5 opacity-70" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[16rem]">
        <DropdownMenuLabel>Switch project</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {ordered.map((p) => (
          <DropdownMenuItem key={p.id} onSelect={() => switchTo(p.id)}>
            <span className="flex-1 truncate">{p.name}{pins.data?.includes(p.id)?' · Pinned':''}</span>
            {p.id === currentProjectId && <Check className="h-4 w-4" />}
          </DropdownMenuItem>
        ))}
        {others.length === 0 && (
          <div className="px-2 py-1.5 text-xs text-[--color-text-muted]">
            No other projects in this workspace.
          </div>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
