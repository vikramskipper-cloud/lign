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
import { useWorkspaces } from '@/shell/queries'
import { Skeleton } from '@/ui/skeleton'

interface Props {
  currentWorkspaceId: string
  currentName?: string
}

const LAST_WS_KEY = 'lign.lastWorkspaceId'

export function persistLastWorkspace(id: string) {
  try {
    localStorage.setItem(LAST_WS_KEY, id)
  } catch {
    /* localStorage may be blocked; not fatal */
  }
}

export function readLastWorkspace(): string | null {
  try {
    return localStorage.getItem(LAST_WS_KEY)
  } catch {
    return null
  }
}

/**
 * Top-bar workspace switcher. Hidden entirely when the user has exactly 1
 * workspace (APP 002 §6). Persists last choice to localStorage.
 */
export function WorkspaceSwitcher({ currentWorkspaceId, currentName }: Props) {
  const { data, isLoading } = useWorkspaces()
  const navigate = useNavigate()

  if (isLoading) return <Skeleton className="h-8 w-32" />
  if (!data || data.length <= 1) {
    return currentName ? (
      <span className="text-sm font-medium text-[--color-text]">{currentName}</span>
    ) : null
  }

  const switchTo = (id: string) => {
    persistLastWorkspace(id)
    navigate(`/workspace/${id}/projects`)
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm" className="gap-1.5 -ml-2">
          <span className="max-w-[12rem] truncate">{currentName ?? 'Workspace'}</span>
          <ChevronDown className="h-4 w-4 opacity-70" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[14rem]">
        <DropdownMenuLabel>Switch workspace</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {data.map((ws) => (
          <DropdownMenuItem key={ws.id} onSelect={() => switchTo(ws.id)}>
            <span className="flex-1 truncate">{ws.name}</span>
            {ws.id === currentWorkspaceId && <Check className="h-4 w-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
