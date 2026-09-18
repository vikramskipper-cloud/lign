import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { FormRow } from '@/ui/form-row'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { humanizeError, validateName } from '@/features/shared/errors'
import type { ProjectRow } from '@/shell/queries'

interface Props {
  project: ProjectRow
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EditProjectDialog({ project, open, onOpenChange }: Props) {
  const qc = useQueryClient()
  const [name, setName] = React.useState(project.name)
  const [code, setCode] = React.useState(project.code ?? '')
  const [description, setDescription] = React.useState(project.description ?? '')
  const [error, setError] = React.useState<string | undefined>()

  React.useEffect(() => {
    if (open) {
      setName(project.name)
      setCode(project.code ?? '')
      setDescription(project.description ?? '')
      setError(undefined)
    }
  }, [open, project])

  const mutation = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from('projects')
        .update({
          name: name.trim(),
          code: code.trim() || null,
          description: description.trim() || null,
        })
        .eq('id', project.id)
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Project updated')
      qc.invalidateQueries({ queryKey: qk.project(project.id) })
      qc.invalidateQueries({ queryKey: qk.projects(project.workspace_id) })
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
          <DialogTitle>Edit project</DialogTitle>
          <DialogDescription>Slug can't be changed once the project is created.</DialogDescription>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="ep-name" label="Name" required error={error}>
            <Input
              id="ep-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              disabled={mutation.isPending}
            />
          </FormRow>
          <FormRow htmlFor="ep-code" label="Code" hint="Optional short label (e.g. KIT-2026).">
            <Input
              id="ep-code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              disabled={mutation.isPending}
            />
          </FormRow>
          <FormRow htmlFor="ep-desc" label="Description">
            <Input
              id="ep-desc"
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
