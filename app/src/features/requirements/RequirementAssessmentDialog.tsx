import * as React from 'react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import { Button } from '@/ui/button'
import { FormRow } from '@/ui/form-row'
import { useAssessVersionRequirement } from './mutations'
import type { AssessmentStatus } from './queries'

interface Props {
  workspaceId: string
  requirementId: string
  requirementCode: string
  assetVersionId: string
  previousStatus?: AssessmentStatus | null
  previousNote?: string | null
  open: boolean
  onOpenChange: (open: boolean) => void
}

const OPTIONS: AssessmentStatus[] = [
  'satisfied',
  'partial',
  'not_satisfied',
  'not_applicable',
]

export function RequirementAssessmentDialog({
  workspaceId,
  requirementId,
  requirementCode,
  assetVersionId,
  previousStatus,
  previousNote,
  open,
  onOpenChange,
}: Props) {
  const [status, setStatus] = React.useState<AssessmentStatus>(
    previousStatus ?? 'satisfied',
  )
  const [note, setNote] = React.useState(previousNote ?? '')

  React.useEffect(() => {
    if (open) {
      setStatus(previousStatus ?? 'satisfied')
      setNote(previousNote ?? '')
    }
  }, [open, previousStatus, previousNote])

  const assess = useAssessVersionRequirement(workspaceId)

  const submit = async () => {
    if (note.length > 4000) return
    await assess.mutateAsync({
      assetVersionId,
      requirementId,
      status,
      note: note.trim() || null,
    })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Assess {requirementCode}</DialogTitle>
          <DialogDescription>
            Record whether this version satisfies the requirement. This becomes
            an immutable historical fact for release-readiness computation.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <FormRow label="Status">
            <select
              className="w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm"
              value={status}
              onChange={(e) => setStatus(e.target.value as AssessmentStatus)}
            >
              {OPTIONS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </FormRow>
          <FormRow label="Note (optional)">
            <textarea
              className="min-h-24 w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm outline-none focus-visible:ring-1 focus-visible:ring-[--color-border-strong]"
              value={note}
              maxLength={4000}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Compliance evidence, deviation reason, follow-up action…"
            />
            <div className="mt-1 text-[10px] text-[--color-text-subtle]">
              {note.length} / 4000
            </div>
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
          <Button size="sm" onClick={submit} disabled={assess.isPending}>
            Record
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
