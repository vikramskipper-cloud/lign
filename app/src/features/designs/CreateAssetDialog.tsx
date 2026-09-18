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
import { useSession } from '@/auth/SessionProvider'
import { qk } from '@/lib/queryKeys'
import { invalidateAssetsForProject, invalidateAllNeighbors } from '@/features/shared/invalidate'
import { humanizeError, validateName } from '@/features/shared/errors'
import { DisciplineCombobox } from '@/features/disciplines/DisciplineCombobox'

interface Props {
  workspaceId: string
  projectId: string
  presetCollectionId?: string | null
  canCreateDiscipline: boolean
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function CreateAssetDialog({
  workspaceId,
  projectId,
  presetCollectionId,
  canCreateDiscipline,
  open,
  onOpenChange,
}: Props) {
  const qc = useQueryClient()
  const { user } = useSession()
  const [name, setName] = React.useState('')
  const [code, setCode] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [disciplineId, setDisciplineId] = React.useState<string | null>(null)
  const [error, setError] = React.useState<string | undefined>()

  React.useEffect(() => {
    if (!open) {
      setName('')
      setCode('')
      setDescription('')
      setDisciplineId(null)
      setError(undefined)
    }
  }, [open])

  const mutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from('design_assets').insert({
        workspace_id: workspaceId,
        project_id: projectId,
        collection_id: presetCollectionId ?? null,
        discipline_id: disciplineId,
        name: name.trim(),
        code: code.trim() || null,
        description: description.trim() || null,
        created_by_profile_id: user?.id,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Asset created')
      invalidateAssetsForProject(qc, projectId)
      invalidateAllNeighbors(qc)
      qc.invalidateQueries({ queryKey: qk.disciplines(projectId) })
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
          <DialogTitle>New design asset</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="a-name" label="Name" required error={error}>
            <Input
              id="a-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              disabled={mutation.isPending}
              placeholder="Kitchen layout"
            />
          </FormRow>
          <FormRow htmlFor="a-code" label="Code" hint="Optional short label (e.g. KIT-014).">
            <Input
              id="a-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              disabled={mutation.isPending}
            />
          </FormRow>
          <FormRow label="Discipline" hint="What kind of design is this?">
            <DisciplineCombobox
              workspaceId={workspaceId}
              projectId={projectId}
              value={disciplineId}
              onChange={setDisciplineId}
              canCreate={canCreateDiscipline}
              allowNone
              disabled={mutation.isPending}
            />
          </FormRow>
          <FormRow htmlFor="a-desc" label="Description">
            <Input
              id="a-desc"
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
              {mutation.isPending ? 'Creating…' : 'Create asset'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
