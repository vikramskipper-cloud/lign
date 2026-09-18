import * as React from 'react'
import { useNavigate } from 'react-router'
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
import { useCreateRequirement } from './mutations'
import type {
  RequirementCategoryKind,
  RequirementPriority,
  RequirementSourceKind,
} from './queries'

interface Props {
  workspaceId: string
  projectId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

const PRIORITIES: RequirementPriority[] = [
  'critical',
  'high',
  'medium',
  'low',
  'informational',
]

const SOURCE_KINDS: RequirementSourceKind[] = [
  'client',
  'consultant',
  'regulatory',
  'internal_team',
  'qa',
  'procurement',
  'manufacturing',
  'safety',
  'contractual',
  'other',
]

const CATEGORY_KINDS: RequirementCategoryKind[] = [
  'functional',
  'non_functional',
  'regulatory',
  'contractual',
  'technical',
  'aesthetic',
  'sustainability',
  'safety',
  'operational',
  'other',
]

export function CreateRequirementDialog({
  workspaceId,
  projectId,
  open,
  onOpenChange,
}: Props) {
  const nav = useNavigate()
  const [title, setTitle] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [sourceRef, setSourceRef] = React.useState('')
  const [priority, setPriority] = React.useState<RequirementPriority>('medium')
  const [sourceKind, setSourceKind] = React.useState<
    RequirementSourceKind | ''
  >('')
  const [categoryKind, setCategoryKind] = React.useState<
    RequirementCategoryKind | ''
  >('')
  const [dueAt, setDueAt] = React.useState<string>('')

  const create = useCreateRequirement(workspaceId, projectId)

  const reset = () => {
    setTitle('')
    setDescription('')
    setSourceRef('')
    setPriority('medium')
    setSourceKind('')
    setCategoryKind('')
    setDueAt('')
  }

  const submit = async (activate: boolean) => {
    if (!title.trim()) return
    const r = await create.mutateAsync({
      workspaceId,
      projectId,
      title: title.trim(),
      description: description.trim() || null,
      sourceRef: sourceRef.trim() || null,
      priority,
      sourceKind: sourceKind || null,
      categoryKind: categoryKind || null,
      dueAt: dueAt ? new Date(dueAt).toISOString() : null,
      status: activate ? 'active' : 'draft',
    })
    reset()
    onOpenChange(false)
    nav(
      `/workspace/${workspaceId}/project/${projectId}/requirement/${r.requirementId}`,
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>New requirement</DialogTitle>
          <DialogDescription>
            The server assigns the code (R-NNN) automatically. Save as draft to
            iterate; publish to make it binding.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <FormRow label="Title">
            <Input
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Short, imperative statement"
            />
          </FormRow>
          <FormRow label="Description">
            <textarea
              className="min-h-24 w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm outline-none focus-visible:ring-1 focus-visible:ring-[--color-border-strong]"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Full requirement text, references, acceptance criteria"
            />
          </FormRow>
          <div className="grid grid-cols-2 gap-3">
            <FormRow label="Priority">
              <select
                className="w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm"
                value={priority}
                onChange={(e) =>
                  setPriority(e.target.value as RequirementPriority)
                }
              >
                {PRIORITIES.map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </select>
            </FormRow>
            <FormRow label="Due">
              <Input
                type="datetime-local"
                value={dueAt}
                onChange={(e) => setDueAt(e.target.value)}
              />
            </FormRow>
            <FormRow label="Source">
              <select
                className="w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm"
                value={sourceKind}
                onChange={(e) =>
                  setSourceKind(e.target.value as RequirementSourceKind | '')
                }
              >
                <option value="">Unset</option>
                {SOURCE_KINDS.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </FormRow>
            <FormRow label="Category">
              <select
                className="w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm"
                value={categoryKind}
                onChange={(e) =>
                  setCategoryKind(
                    e.target.value as RequirementCategoryKind | '',
                  )
                }
              >
                <option value="">Unset</option>
                {CATEGORY_KINDS.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </FormRow>
          </div>
          <FormRow label="Source reference">
            <Input
              value={sourceRef}
              onChange={(e) => setSourceRef(e.target.value)}
              placeholder="e.g. NFPA 13 §14.2.3 or JIRA-4821"
            />
          </FormRow>
        </div>
        <DialogFooter>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => onOpenChange(false)}
          >
            Cancel
          </Button>
          <Button
            size="sm"
            variant="secondary"
            disabled={!title.trim() || create.isPending}
            onClick={() => submit(false)}
          >
            Save draft
          </Button>
          <Button
            size="sm"
            disabled={!title.trim() || create.isPending}
            onClick={() => submit(true)}
          >
            Publish
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
