import * as React from 'react'
import { Check, Copy, Link2 } from 'lucide-react'
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
import { Label } from '@/ui/label'
import { FormRow } from '@/ui/form-row'
import { absolute, relative } from '@/lib/formatDate'
import { PROJECT_ROLES, WORKSPACE_ROLES } from './queries'
import type { ProjectRole, WorkspaceRole } from './queries'
import { inviteUrl, useInviteMember, useInviteStakeholder, type InviteResult } from './mutations'

type Mode = 'member' | 'stakeholder'

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  workspaceId: string
  mode: Mode
  /** Required for stakeholders: they see nothing without project scope. */
  projectId?: string
  projectName?: string
}

/**
 * Invite flow, copy-link delivery.
 *
 * There is no email infrastructure in this project, so the token is shown once
 * and the admin sends it themselves. That is a real constraint, not a
 * placeholder — the UI says so plainly rather than implying a mail is on its
 * way. Only the sha256 of this token ever reaches the database, which is also
 * why it cannot be shown again later.
 */
export function InviteDialog({
  open,
  onOpenChange,
  workspaceId,
  mode,
  projectId,
  projectName,
}: Props) {
  const [email, setEmail] = React.useState('')
  const [displayName, setDisplayName] = React.useState('')
  const [wsRole, setWsRole] = React.useState<WorkspaceRole>('member')
  const [projRole, setProjRole] = React.useState<ProjectRole>('reviewer')
  const [result, setResult] = React.useState<InviteResult | null>(null)
  const [copied, setCopied] = React.useState(false)

  const inviteMember = useInviteMember(workspaceId)
  const inviteStakeholder = useInviteStakeholder(workspaceId)
  const pending = inviteMember.isPending || inviteStakeholder.isPending

  const reset = () => {
    setEmail('')
    setDisplayName('')
    setWsRole('member')
    setProjRole('reviewer')
    setResult(null)
    setCopied(false)
  }

  const close = (next: boolean) => {
    if (!next) reset()
    onOpenChange(next)
  }

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (pending || !email.trim()) return
    try {
      if (mode === 'member') {
        setResult(await inviteMember.mutateAsync({ email, role: wsRole }))
      } else {
        if (!projectId) return
        setResult(
          await inviteStakeholder.mutateAsync({
            email,
            projectId,
            role: projRole,
            displayName: displayName || null,
          }),
        )
      }
    } catch {
      /* toast already raised by the mutation */
    }
  }

  const copy = async () => {
    if (!result) return
    try {
      await navigator.clipboard.writeText(inviteUrl(result.token))
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      toast.error('Could not copy — select the link and copy it manually')
    }
  }

  return (
    <Dialog open={open} onOpenChange={close}>
      <DialogContent className="sm:max-w-md">
        {result ? (
          <>
            <DialogHeader>
              <DialogTitle>Invitation created</DialogTitle>
              <DialogDescription>
                Send this link to {email}. It expires {relative(result.expiresAt)} ({absolute(result.expiresAt)}) and can be
                used once.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-3">
              <div className="flex items-center gap-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface-2] p-2">
                <Link2 className="h-4 w-4 shrink-0 text-[--color-text-subtle]" />
                <code className="min-w-0 flex-1 truncate text-xs">{inviteUrl(result.token)}</code>
                <Button type="button" size="sm" variant="ghost" onClick={copy}>
                  {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                </Button>
              </div>
              <p className="text-xs text-[--color-text-muted]">
                Copy it now — only a hash is stored, so this link cannot be shown again. If you
                lose it, revoke the invitation and send a new one.
              </p>
            </div>

            <DialogFooter>
              <Button variant="ghost" onClick={() => reset()}>
                Invite someone else
              </Button>
              <Button onClick={() => close(false)}>Done</Button>
            </DialogFooter>
          </>
        ) : (
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>
                {mode === 'member' ? 'Invite a workspace member' : 'Invite an external stakeholder'}
              </DialogTitle>
              <DialogDescription>
                {mode === 'member'
                  ? 'They join the workspace, then get added to projects individually.'
                  : `They get access to ${projectName ?? 'this project'} only, and never a workspace role.`}
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-2">
              <FormRow label="Email" htmlFor="invite-email">
                <Input
                  id="invite-email"
                  type="email"
                  required
                  autoFocus
                  placeholder="person@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={pending}
                />
              </FormRow>

              {mode === 'stakeholder' && (
                <FormRow label="Name (optional)" htmlFor="invite-name">
                  <Input
                    id="invite-name"
                    value={displayName}
                    onChange={(e) => setDisplayName(e.target.value)}
                    disabled={pending}
                  />
                </FormRow>
              )}

              <div className="space-y-1.5">
                <Label htmlFor="invite-role">
                  {mode === 'member' ? 'Workspace role' : 'Project role'}
                </Label>
                <select
                  id="invite-role"
                  className="h-9 w-full rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-2 text-sm"
                  value={mode === 'member' ? wsRole : projRole}
                  disabled={pending}
                  onChange={(e) =>
                    mode === 'member'
                      ? setWsRole(e.target.value as WorkspaceRole)
                      : setProjRole(e.target.value as ProjectRole)
                  }
                >
                  {(mode === 'member' ? WORKSPACE_ROLES : PROJECT_ROLES).map((r) => (
                    <option key={r} value={r}>
                      {r}
                    </option>
                  ))}
                </select>
                {mode === 'member' && wsRole === 'owner' && (
                  <p className="text-xs text-[--color-text-muted]">
                    Only an existing owner can invite an owner.
                  </p>
                )}
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={() => close(false)} disabled={pending}>
                Cancel
              </Button>
              <Button type="submit" disabled={pending || !email.trim()}>
                {pending ? 'Creating…' : 'Create invite link'}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}
