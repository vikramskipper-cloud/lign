import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import * as Popover from '@radix-ui/react-popover'
import { ChevronDown, Check, Plus, X } from 'lucide-react'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useSession } from '@/auth/SessionProvider'
import { humanizeError, validateName } from '@/features/shared/errors'
import { useDisciplines } from './queries'
import { cn } from '@/lib/cn'

interface Props {
  workspaceId: string
  projectId: string
  value: string | null
  onChange: (id: string | null) => void
  canCreate: boolean
  allowNone?: boolean
  disabled?: boolean
}

/**
 * Combobox used inside CreateAssetDialog + DetailsPanel picker.
 * If the typed string doesn't match any discipline and canCreate is true,
 * offers "+ Create '{typed}'".
 */
export function DisciplineCombobox({
  workspaceId,
  projectId,
  value,
  onChange,
  canCreate,
  allowNone = false,
  disabled,
}: Props) {
  const { data } = useDisciplines(projectId)
  const items = data ?? []
  const selected = items.find((d) => d.id === value)
  const [open, setOpen] = React.useState(false)
  const [query, setQuery] = React.useState('')
  const qc = useQueryClient()
  const { user } = useSession()

  const q = query.trim().toLowerCase()
  const filtered = q
    ? items.filter((d) => d.name.toLowerCase().includes(q))
    : items
  const exactMatch = q && items.some((d) => d.name.toLowerCase() === q)

  const create = useMutation({
    mutationFn: async (name: string) => {
      const err = validateName(name, 80)
      if (err) throw new Error(err)
      const { data, error } = await supabase
        .from('disciplines')
        .insert({
          workspace_id: workspaceId,
          project_id: projectId,
          name: name.trim(),
          created_by_profile_id: user?.id,
        })
        .select('id')
        .single()
      if (error) throw error
      return data.id as string
    },
    onSuccess: (id) => {
      qc.invalidateQueries({ queryKey: qk.disciplines(projectId) })
      onChange(id)
      setQuery('')
      setOpen(false)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  React.useEffect(() => {
    if (!open) setQuery('')
  }, [open])

  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger asChild>
        <Button
          type="button"
          variant="secondary"
          size="sm"
          disabled={disabled}
          className="w-full justify-between font-normal"
        >
          <span className={cn(!selected && 'text-[--color-text-muted]')}>
            {selected ? selected.name : 'Select discipline…'}
          </span>
          <ChevronDown className="ml-1 h-4 w-4 shrink-0" />
        </Button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content
          sideOffset={4}
          align="start"
          className="z-50 w-[--radix-popover-trigger-width] min-w-[14rem] rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-1 shadow-[--shadow-md]"
        >
          <div className="flex items-center gap-1 border-b border-[--color-border] p-1">
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search or create…"
              autoFocus
              className="h-8"
            />
            {selected && allowNone && (
              <Button
                variant="ghost"
                size="icon"
                aria-label="Clear"
                className="h-8 w-8"
                onClick={() => {
                  onChange(null)
                  setOpen(false)
                }}
              >
                <X className="h-4 w-4" />
              </Button>
            )}
          </div>
          <div className="max-h-56 overflow-y-auto py-1">
            {filtered.map((d) => (
              <button
                key={d.id}
                type="button"
                onClick={() => {
                  onChange(d.id)
                  setOpen(false)
                }}
                className={cn(
                  'flex w-full items-center justify-between rounded-[--radius-sm] px-2 py-1.5 text-left text-sm hover:bg-[--color-surface-2]',
                )}
              >
                <span className="truncate">{d.name}</span>
                {value === d.id && <Check className="h-4 w-4 text-[--color-brand]" />}
              </button>
            ))}
            {filtered.length === 0 && !q && (
              <p className="px-2 py-2 text-xs text-[--color-text-subtle]">No disciplines yet.</p>
            )}
            {q && !exactMatch && canCreate && (
              <button
                type="button"
                onClick={() => create.mutate(query)}
                disabled={create.isPending}
                className="flex w-full items-center gap-2 rounded-[--radius-sm] px-2 py-1.5 text-left text-sm hover:bg-[--color-surface-2]"
              >
                <Plus className="h-4 w-4 text-[--color-text-muted]" />
                <span>
                  Create <span className="font-medium">"{query.trim()}"</span>
                </span>
              </button>
            )}
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  )
}
