import * as React from 'react'
import { MoreHorizontal } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { FormRow } from '@/ui/form-row'
import { Input } from '@/ui/input'
import {
  useDiscardReleaseDraft,
  usePublishRelease,
  useWithdrawRelease,
} from './mutations'
import type { CapabilityMap } from '@/types/capabilities'
import type { ReleaseDetail, ReleaseType } from './queries'
import { RELEASE_TYPES } from './queries'

interface Props {
  workspaceId: string
  projectId: string
  release: ReleaseDetail
  caps: CapabilityMap | undefined
}

export function ReleaseActions({ workspaceId, projectId, release, caps }: Props) {
  const canFinalize = Boolean(caps?.['release.finalize'])
  const canWithdraw = Boolean(caps?.['release.withdraw'])
  const canCreate = Boolean(caps?.['release.create'])
  const [publishOpen, setPublishOpen] = React.useState(false)
  const [withdrawOpen, setWithdrawOpen] = React.useState(false)

  const publish = usePublishRelease(workspaceId, projectId)
  const withdraw = useWithdrawRelease(workspaceId, projectId)
  const discard = useDiscardReleaseDraft(workspaceId, projectId)

  return (
    <div className="flex items-center gap-2">
      {release.status === 'draft' && canFinalize && (
        <Button size="sm" onClick={() => setPublishOpen(true)}>
          Publish
        </Button>
      )}
      {release.status === 'released' && canWithdraw && (
        <Button
          size="sm"
          variant="secondary"
          onClick={() => setWithdrawOpen(true)}
        >
          Withdraw
        </Button>
      )}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button size="icon" variant="secondary" aria-label="Release actions">
            <MoreHorizontal className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-[10rem]">
          {release.status === 'draft' && canCreate && (
            <DropdownMenuItem
              onSelect={() => discard.mutate(release.id)}
              className="text-[--color-danger]"
            >
              Discard draft
            </DropdownMenuItem>
          )}
          {release.status !== 'draft' && (
            <>
              <DropdownMenuItem disabled>Bookmark (Wave 3)</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem disabled>
                Export audit (reserved)
              </DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {publishOpen && (
        <PublishDialog
          release={release}
          onCancel={() => setPublishOpen(false)}
          onConfirm={async (t) => {
            await publish.mutateAsync({
              releaseId: release.id,
              releaseType: t,
            })
            setPublishOpen(false)
          }}
          isPending={publish.isPending}
        />
      )}
      {withdrawOpen && (
        <WithdrawDialog
          release={release}
          onCancel={() => setWithdrawOpen(false)}
          onConfirm={async (reason) => {
            await withdraw.mutateAsync({
              releaseId: release.id,
              reason,
            })
            setWithdrawOpen(false)
          }}
          isPending={withdraw.isPending}
        />
      )}
    </div>
  )
}

function PublishDialog({
  release,
  onCancel,
  onConfirm,
  isPending,
}: {
  release: ReleaseDetail
  onCancel: () => void
  onConfirm: (t: ReleaseType | null) => Promise<void>
  isPending: boolean
}) {
  const [type, setType] = React.useState<ReleaseType | ''>(
    release.release_type ?? '',
  )
  return (
    <Dialog open onOpenChange={(o) => !o && onCancel()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Publish release</DialogTitle>
          <DialogDescription>
            Publishing is server-authoritative: the DB verifies every item is
            approved and captures an immutable evidence snapshot. Regulatory /
            final releases require zero critical unsatisfied requirements.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <FormRow label="Release type">
            <select
              className="w-full rounded-[--radius-sm] border border-[--color-border] bg-[--color-surface] px-2 py-1.5 text-sm"
              value={type}
              onChange={(e) => setType(e.target.value as ReleaseType | '')}
            >
              <option value="">Keep current ({release.release_type ?? 'unset'})</option>
              {RELEASE_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </FormRow>
        </div>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={onCancel}>
            Cancel
          </Button>
          <Button
            size="sm"
            disabled={isPending}
            onClick={() => onConfirm((type || null) as ReleaseType | null)}
          >
            Publish
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function WithdrawDialog({
  onCancel,
  onConfirm,
  isPending,
}: {
  release: ReleaseDetail
  onCancel: () => void
  onConfirm: (reason: string) => Promise<void>
  isPending: boolean
}) {
  const [reason, setReason] = React.useState('')
  return (
    <Dialog open onOpenChange={(o) => !o && onCancel()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Withdraw release</DialogTitle>
          <DialogDescription>
            Withdrawal is terminal — a withdrawn release cannot be re-released.
            The evidence snapshot remains locked for audit.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <FormRow label="Reason">
            <Input
              autoFocus
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Required — why is this being withdrawn?"
            />
          </FormRow>
        </div>
        <DialogFooter>
          <Button variant="secondary" size="sm" onClick={onCancel}>
            Cancel
          </Button>
          <Button
            size="sm"
            variant="destructive"
            disabled={isPending || !reason.trim()}
            onClick={() => onConfirm(reason.trim())}
          >
            Withdraw
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
