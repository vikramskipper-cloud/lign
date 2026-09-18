import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { FormRow } from '@/ui/form-row'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useSession } from '@/auth/SessionProvider'
import { humanizeError, validateName } from '@/features/shared/errors'
import type { CollectionRow } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  collection?: CollectionRow
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function CollectionDialog({
  workspaceId,
  projectId,
  collection,
  open,
  onOpenChange,
}: Props) {
  const qc = useQueryClient()
  const { user } = useSession()
  const isEdit = Boolean(collection)
  const [name, setName] = React.useState(collection?.name ?? '')
  const [description, setDescription] = React.useState(collection?.description ?? '')
  const [error, setError] = React.useState<string | undefined>()

  React.useEffect(() => {
    if (open) {
      setName(collection?.name ?? '')
      setDescription(collection?.description ?? '')
      setError(undefined)
    }
  }, [open, collection])

  const mutation = useMutation({
    mutationFn: async () => {
      if (isEdit && collection) {
        const { error } = await supabase
          .from('collections')
          .update({
            name: name.trim(),
            description: description.trim() || null,
          })
          .eq('id', collection.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('collections').insert({
          workspace_id: workspaceId,
          project_id: projectId,
          name: name.trim(),
          description: description.trim() || null,
          created_by_profile_id: user?.id,
        })
        if (error) throw error
      }
    },
    onSuccess: () => {
      toast.success(isEdit ? 'Collection updated' : 'Collection created')
      qc.invalidateQueries({ queryKey: qk.collections(projectId) })
      onOpenChange(false)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const nameErr = validateName(name)
    setError(nameErr ?? undefined)
    if (nameErr) return
    mutation.mutate()
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? 'Edit collection' : 'New collection'}</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="c-name" label="Name" required error={error}>
            <Input
              id="c-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              disabled={mutation.isPending}
              placeholder="Kitchens"
            />
          </FormRow>
          <FormRow htmlFor="c-desc" label="Description" hint="Optional.">
            <Input
              id="c-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={mutation.isPending}
            />
          </FormRow>
          <DialogFooter>
            <Button
              type="button"
              variant="secondary"
              size="sm"
              onClick={() => onOpenChange(false)}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" size="sm" disabled={mutation.isPending}>
              {mutation.isPending ? 'Saving…' : isEdit ? 'Save changes' : 'Create'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
