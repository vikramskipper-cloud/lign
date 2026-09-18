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
import { useCreateReleaseDraft } from './mutations'
import { RELEASE_TYPES, type ReleaseType } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function CreateReleaseDialog({
  workspaceId,
  projectId,
  open,
  onOpenChange,
}: Props) {
  const nav = useNavigate()
  const [name, setName] = React.useState('')
  const [notes, setNotes] = React.useState('')
  const [channel, setChannel] = React.useState('')
  const [releaseType, setReleaseType] = React.useState<ReleaseType | ''>('')

  const create = useCreateReleaseDraft(workspaceId, projectId)

  const reset = () => {
    setName('')
    setNotes('')
    setChannel('')
    setReleaseType('')
  }

  const submit = async () => {
    if (!name.trim()) return
    const id = await create.mutateAsync({
      workspaceId,
      projectId,
      name: name.trim(),
      notes: notes.trim() || null,
      channel: channel.trim() || null,
      releaseType: (releaseType || null) as ReleaseType | null,
    })
    reset()
    onOpenChange(false)
    nav(`/workspace/${workspaceId}/project/${projectId}/release/${id}`)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>New release draft</DialogTitle>
          <DialogDescription>
            The server assigns the code (R-NNN) automatically. Compose items, verify
            evidence readiness, then publish from the detail page.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <FormRow label="Name">
            <Input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Q1 Client Package"
            />
          </FormRow>
          <FormRow label="Notes">
            <textarea
              className="min-h-24 w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm outline-none focus-visible:ring-1 focus-visible:ring-[--color-border-strong]"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Optional context, changelog, distribution notes"
            />
          </FormRow>
          <div className="grid grid-cols-2 gap-3">
            <FormRow label="Release type">
              <select
                className="w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm"
                value={releaseType}
                onChange={(e) =>
                  setReleaseType(e.target.value as ReleaseType | '')
                }
              >
                <option value="">Unset</option>
                {RELEASE_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </FormRow>
            <FormRow label="Channel (label)">
              <Input
                value={channel}
                onChange={(e) => setChannel(e.target.value)}
                placeholder="Optional free-form label"
              />
            </FormRow>
          </div>
          <p className="text-[11px] text-[--color-text-subtle]">
            Publish is server-authoritative: the composer will show a per-item
            readiness preview before publish, and the DB trigger will re-verify
            every item is approved. `regulatory` and `final` types additionally
            require zero critical unsatisfied requirements.
          </p>
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
            disabled={!name.trim() || create.isPending}
            onClick={submit}
          >
            Create draft
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
