import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Layers, Inbox, Plus, MoreVertical, Pencil, Archive } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { Skeleton } from '@/ui/skeleton'
import { cn } from '@/lib/cn'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { invalidateAssetsForProject, invalidateAllNeighbors } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { useCollections, type CollectionRow } from './queries'
import { CollectionDialog } from './CollectionDialog'

interface Props {
  workspaceId: string
  projectId: string
  value: string | null | 'unfiled'
  onChange: (value: string | null | 'unfiled') => void
  canCreate: boolean
  canEdit: boolean
  canArchive: boolean
}

export function CollectionSidebar({
  workspaceId,
  projectId,
  value,
  onChange,
  canCreate,
  canEdit,
  canArchive,
}: Props) {
  const { data, isLoading } = useCollections(projectId)
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const [editing, setEditing] = React.useState<CollectionRow | undefined>()

  const qc = useQueryClient()
  const archive = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('collections')
        .update({ status: 'archived', archived_at: new Date().toISOString() })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Collection archived')
      qc.invalidateQueries({ queryKey: qk.collections(projectId) })
      invalidateAssetsForProject(qc, projectId)
      invalidateAllNeighbors(qc)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const items = data ?? []

  return (
    <aside className="flex h-full w-56 shrink-0 flex-col gap-1 border-r border-[--color-border] bg-[--color-surface] p-3">
      <div className="mb-1 px-2 text-xs font-medium uppercase tracking-wide text-[--color-text-subtle]">
        Collections
      </div>

      <SidebarItem
        icon={<Layers className="h-4 w-4" />}
        label="All"
        active={value === null}
        onSelect={() => onChange(null)}
      />
      <SidebarItem
        icon={<Inbox className="h-4 w-4" />}
        label="Unfiled"
        active={value === 'unfiled'}
        onSelect={() => onChange('unfiled')}
      />

      <div className="my-2 h-px bg-[--color-border]" />

      {isLoading ? (
        <div className="space-y-1">
          <Skeleton className="h-7 w-full" />
          <Skeleton className="h-7 w-full" />
        </div>
      ) : items.length === 0 ? (
        <p className="px-2 py-1 text-xs text-[--color-text-subtle]">No collections yet.</p>
      ) : (
        items.map((c) => (
          <div key={c.id} className="group relative">
            <SidebarItem
              label={c.name}
              active={value === c.id}
              onSelect={() => onChange(c.id)}
            />
            {(canEdit || canArchive) && (
              <div className="absolute right-1 top-1/2 -translate-y-1/2 opacity-0 group-hover:opacity-100 focus-within:opacity-100">
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={`Actions for ${c.name}`}
                      className="h-6 w-6"
                    >
                      <MoreVertical className="h-3.5 w-3.5" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    {canEdit && (
                      <DropdownMenuItem
                        onSelect={() => {
                          setEditing(c)
                          setDialogOpen(true)
                        }}
                      >
                        <Pencil className="h-4 w-4" />
                        Rename
                      </DropdownMenuItem>
                    )}
                    {canArchive && (
                      <DropdownMenuItem
                        className="text-[--color-danger]"
                        onSelect={() => {
                          if (
                            window.confirm(
                              `Archive "${c.name}"? Assets in this collection will move to Unfiled.`,
                            )
                          ) {
                            archive.mutate(c.id)
                            if (value === c.id) onChange(null)
                          }
                        }}
                      >
                        <Archive className="h-4 w-4" />
                        Archive
                      </DropdownMenuItem>
                    )}
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            )}
          </div>
        ))
      )}

      {canCreate && (
        <>
          <div className="my-2 h-px bg-[--color-border]" />
          <Button
            variant="ghost"
            size="sm"
            className="justify-start"
            onClick={() => {
              setEditing(undefined)
              setDialogOpen(true)
            }}
          >
            <Plus className="mr-1 h-4 w-4" />
            New collection
          </Button>
        </>
      )}

      <CollectionDialog
        workspaceId={workspaceId}
        projectId={projectId}
        collection={editing}
        open={dialogOpen}
        onOpenChange={(o) => {
          setDialogOpen(o)
          if (!o) setEditing(undefined)
        }}
      />
    </aside>
  )
}

function SidebarItem({
  icon,
  label,
  active,
  onSelect,
}: {
  icon?: React.ReactNode
  label: string
  active: boolean
  onSelect: () => void
}) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        'flex w-full items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-left text-sm',
        active
          ? 'bg-[--color-surface-2] text-[--color-text] font-medium'
          : 'text-[--color-text-muted] hover:bg-[--color-surface-2] hover:text-[--color-text]',
      )}
    >
      {icon}
      <span className="truncate">{label}</span>
    </button>
  )
}
