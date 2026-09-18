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
import { invalidateAssetsForProject, invalidateNeighborsForAsset } from '@/features/shared/invalidate'
import { humanizeError, validateName } from '@/features/shared/errors'
import type { AssetRow } from './queries'

interface Props {
  asset: AssetRow
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EditAssetDialog({ asset, open, onOpenChange }: Props) {
  const qc = useQueryClient()
  const [name, setName] = React.useState(asset.name)
  const [code, setCode] = React.useState(asset.code ?? '')
  const [description, setDescription] = React.useState(asset.description ?? '')
  const [error, setError] = React.useState<string | undefined>()

  React.useEffect(() => {
    if (open) {
      setName(asset.name)
      setCode(asset.code ?? '')
      setDescription(asset.description ?? '')
      setError(undefined)
    }
  }, [open, asset])

  const mutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('design_assets')
        .update({
          name: name.trim(),
          code: code.trim() || null,
          description: description.trim() || null,
        })
        .eq('id', asset.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Asset updated')
      qc.invalidateQueries({ queryKey: qk.asset(asset.id) })
      invalidateAssetsForProject(qc, asset.project_id)
      invalidateNeighborsForAsset(qc, asset.id)
      onOpenChange(false)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const err = validateName(name)
    setError(err ?? undefined)
    if (err) return
    mutation.mutate()
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit asset</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="ea-name" label="Name" required error={error}>
            <Input
              id="ea-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              disabled={mutation.isPending}
            />
          </FormRow>
          <FormRow htmlFor="ea-code" label="Code">
            <Input
              id="ea-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              disabled={mutation.isPending}
            />
          </FormRow>
          <FormRow htmlFor="ea-desc" label="Description">
            <Input
              id="ea-desc"
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
              {mutation.isPending ? 'Saving…' : 'Save changes'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
