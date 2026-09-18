import * as React from 'react'
import { useNavigate } from 'react-router'
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
import { humanizeError, validateName, validateSlug } from '@/features/shared/errors'

interface Props {
  workspaceId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

function slugify(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60)
}

export function CreateProjectDialog({ workspaceId, open, onOpenChange }: Props) {
  const qc = useQueryClient()
  const navigate = useNavigate()
  const [name, setName] = React.useState('')
  const [slug, setSlug] = React.useState('')
  const [slugTouched, setSlugTouched] = React.useState(false)
  const [description, setDescription] = React.useState('')
  const [errors, setErrors] = React.useState<{ name?: string; slug?: string }>({})

  React.useEffect(() => {
    if (!open) {
      setName('')
      setSlug('')
      setSlugTouched(false)
      setDescription('')
      setErrors({})
    }
  }, [open])

  React.useEffect(() => {
    if (!slugTouched) setSlug(slugify(name))
  }, [name, slugTouched])

  const mutation = useMutation({
    mutationFn: async (input: { name: string; slug: string; description: string }) => {
      const { data, error } = await supabase.rpc('create_project', {
        p_workspace_id: workspaceId,
        p_name: input.name.trim(),
        p_slug: input.slug.trim(),
        p_description: input.description.trim() || null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (projectId) => {
      toast.success('Project created')
      qc.invalidateQueries({ queryKey: qk.projects(workspaceId) })
      onOpenChange(false)
      navigate(`/workspace/${workspaceId}/project/${projectId}/overview`)
    },
    onError: (err) => {
      toast.error(humanizeError(err))
    },
  })

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const nameErr = validateName(name)
    const slugErr = validateSlug(slug)
    setErrors({ name: nameErr ?? undefined, slug: slugErr ?? undefined })
    if (nameErr || slugErr) return
    mutation.mutate({ name, slug, description })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New project</DialogTitle>
          <DialogDescription>Projects contain design assets, collections, and disciplines.</DialogDescription>
        </DialogHeader>
        <form onSubmit={onSubmit} className="space-y-4">
          <FormRow htmlFor="p-name" label="Name" required error={errors.name}>
            <Input
              id="p-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              disabled={mutation.isPending}
              placeholder="Kitchen renovation"
            />
          </FormRow>
          <FormRow
            htmlFor="p-slug"
            label="Slug"
            required
            hint="Used in URLs. Lowercase letters, digits, and dashes."
            error={errors.slug}
          >
            <Input
              id="p-slug"
              value={slug}
              onChange={(e) => {
                setSlug(e.target.value)
                setSlugTouched(true)
              }}
              disabled={mutation.isPending}
              placeholder="kitchen-renovation"
            />
          </FormRow>
          <FormRow htmlFor="p-desc" label="Description" hint="Optional.">
            <Input
              id="p-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={mutation.isPending}
              placeholder="Short description of the project."
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
              {mutation.isPending ? 'Creating…' : 'Create project'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
