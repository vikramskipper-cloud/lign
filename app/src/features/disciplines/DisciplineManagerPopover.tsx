import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import * as Popover from '@radix-ui/react-popover'
import { Plus, Check, X, Pencil, Archive } from 'lucide-react'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { Skeleton } from '@/ui/skeleton'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useSession } from '@/auth/SessionProvider'
import { invalidateAssetsForProject } from '@/features/shared/invalidate'
import { humanizeError, validateName } from '@/features/shared/errors'
import { useDisciplines, type DisciplineRow } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  workspaceId: string
  projectId: string
  trigger: React.ReactNode
  canEdit: boolean
  assetCounts?: Record<string, number>
}

/**
 * Inline "Manage disciplines" popover per approved D12.
 * List + add + rename + archive. No dedicated screen.
 */
export function DisciplineManagerPopover({
  workspaceId,
  projectId,
  trigger,
  canEdit,
  assetCounts,
}: Props) {
  const { data, isLoading } = useDisciplines(projectId)
  const [renaming, setRenaming] = React.useState<string | null>(null)
  const [renameValue, setRenameValue] = React.useState('')
  const [adding, setAdding] = React.useState(false)
  const [addValue, setAddValue] = React.useState('')
  const qc = useQueryClient()
  const { user } = useSession()

  const create = useMutation({
    mutationFn: async (name: string) => {
      const err = validateName(name, 80)
      if (err) throw new Error(err)
      const { error } = await supabase.from('disciplines').insert({
        workspace_id: workspaceId,
        project_id: projectId,
        name: name.trim(),
        created_by_profile_id: user?.id,
      })
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: qk.disciplines(projectId) })
      setAdding(false)
      setAddValue('')
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const rename = useMutation({
    mutationFn: async ({ id, name }: { id: string; name: string }) => {
      const err = validateName(name, 80)
      if (err) throw new Error(err)
      const { error } = await supabase
        .from('disciplines')
        .update({ name: name.trim() })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: qk.disciplines(projectId) })
      invalidateAssetsForProject(qc, projectId)
      setRenaming(null)
      setRenameValue('')
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const archive = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .from('disciplines')
        .update({ status: 'archived', archived_at: new Date().toISOString() })
        .eq('id', id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Discipline archived')
      qc.invalidateQueries({ queryKey: qk.disciplines(projectId) })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const items: DisciplineRow[] = data ?? []

  return (
    <Popover.Root>
      <Popover.Trigger asChild>{trigger}</Popover.Trigger>
      <Popover.Portal>
        <Popover.Content
          sideOffset={4}
          align="end"
          className={cn(
            'z-50 w-80 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 shadow-[--shadow-md]',
          )}
        >
          <div className="mb-2 flex items-center justify-between">
            <div className="text-sm font-semibold">Disciplines</div>
            <Popover.Close asChild>
              <Button variant="ghost" size="icon" aria-label="Close" className="h-6 w-6">
                <X className="h-3.5 w-3.5" />
              </Button>
            </Popover.Close>
          </div>

          <div className="max-h-64 space-y-1 overflow-y-auto">
            {isLoading ? (
              <>
                <Skeleton className="h-7 w-full" />
                <Skeleton className="h-7 w-full" />
              </>
            ) : items.length === 0 && !adding ? (
              <p className="px-1 py-2 text-xs text-[--color-text-subtle]">
                No disciplines yet. Add one to start classifying assets.
              </p>
            ) : (
              items.map((d) => {
                const inUse = (assetCounts?.[d.id] ?? 0) > 0
                const isRenaming = renaming === d.id
                return (
                  <div
                    key={d.id}
                    className="group flex items-center gap-1 rounded-[--radius-sm] px-1 py-1 hover:bg-[--color-surface-2]"
                  >
                    {isRenaming ? (
                      <>
                        <Input
                          value={renameValue}
                          onChange={(e) => setRenameValue(e.target.value)}
                          autoFocus
                          className="h-7"
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') rename.mutate({ id: d.id, name: renameValue })
                            if (e.key === 'Escape') setRenaming(null)
                          }}
                        />
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7"
                          onClick={() => rename.mutate({ id: d.id, name: renameValue })}
                          disabled={rename.isPending}
                        >
                          <Check className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7"
                          onClick={() => setRenaming(null)}
                        >
                          <X className="h-3.5 w-3.5" />
                        </Button>
                      </>
                    ) : (
                      <>
                        <span className="flex-1 truncate text-sm">{d.name}</span>
                        {canEdit && (
                          <>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-6 w-6 opacity-0 group-hover:opacity-100 focus-visible:opacity-100"
                              aria-label={`Rename ${d.name}`}
                              onClick={() => {
                                setRenaming(d.id)
                                setRenameValue(d.name)
                              }}
                            >
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-6 w-6 opacity-0 group-hover:opacity-100 focus-visible:opacity-100"
                              aria-label={`Archive ${d.name}`}
                              title={inUse ? 'Reassign assets before archiving.' : undefined}
                              disabled={inUse}
                              onClick={() => {
                                if (window.confirm(`Archive "${d.name}"?`)) archive.mutate(d.id)
                              }}
                            >
                              <Archive className="h-3.5 w-3.5" />
                            </Button>
                          </>
                        )}
                      </>
                    )}
                  </div>
                )
              })
            )}

            {adding && (
              <div className="flex items-center gap-1 rounded-[--radius-sm] px-1 py-1">
                <Input
                  value={addValue}
                  onChange={(e) => setAddValue(e.target.value)}
                  autoFocus
                  className="h-7"
                  placeholder="Discipline name"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') create.mutate(addValue)
                    if (e.key === 'Escape') {
                      setAdding(false)
                      setAddValue('')
                    }
                  }}
                />
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7"
                  disabled={create.isPending}
                  onClick={() => create.mutate(addValue)}
                >
                  <Check className="h-3.5 w-3.5" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => {
                    setAdding(false)
                    setAddValue('')
                  }}
                >
                  <X className="h-3.5 w-3.5" />
                </Button>
              </div>
            )}
          </div>

          {canEdit && !adding && (
            <>
              <div className="my-2 h-px bg-[--color-border]" />
              <Button
                variant="ghost"
                size="sm"
                className="w-full justify-start"
                onClick={() => setAdding(true)}
              >
                <Plus className="mr-1 h-4 w-4" />
                Add discipline
              </Button>
            </>
          )}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  )
}
