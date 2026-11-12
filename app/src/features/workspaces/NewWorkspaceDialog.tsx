import * as React from 'react'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { useAdminOrganizations, useCreateWorkspace, useOrgMembers } from '@/shell/orgQueries'
import { persistLastWorkspace } from '@/shell/WorkspaceSwitcher'
import { useSession } from '@/auth/SessionProvider'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/ui/dialog'
import { Button } from '@/ui/button'
import { Input } from '@/ui/input'
import { Label } from '@/ui/label'
import { humanizeError } from '@/features/shared/errors'

interface Props { open: boolean; onOpenChange: (open: boolean) => void; organizationId?: string }

export function NewWorkspaceDialog({ open, onOpenChange, organizationId }: Props) {
  const orgs = useAdminOrganizations()
  const create = useCreateWorkspace()
  const navigate = useNavigate()
  const { user } = useSession()
  const [name, setName] = React.useState('')
  const [orgId, setOrgId] = React.useState('')
  const [lead, setLead] = React.useState('')
  const [team, setTeam] = React.useState<string[]>([])
  const [error, setError] = React.useState<string | null>(null)
  const options = orgs.data ?? []
  const effectiveOrg = organizationId ?? (orgId || options[0]?.id)
  const members = useOrgMembers(open ? effectiveOrg : undefined)
  const architects = (members.data ?? []).filter((m) => m.status === 'active' && m.userId !== user?.id)
  const inFlight = React.useRef(false)
  React.useEffect(() => {
    if (!open) { setName(''); setOrgId(''); setLead(''); setTeam([]); setError(null); inFlight.current = false }
  }, [open])
  const submit = (event: React.FormEvent) => {
    event.preventDefault()
    if (inFlight.current || !effectiveOrg || !name.trim()) return
    inFlight.current = true
    setError(null)
    create.mutate({ name: name.trim(), organizationId: effectiveOrg, leadUserId: lead || null, memberUserIds: team }, {
      onSuccess: (workspaceId) => {
        persistLastWorkspace(workspaceId)
        toast.success('Workspace and team created')
        onOpenChange(false)
        navigate(`/workspace/${workspaceId}/overview`)
      },
      onError: (err) => { inFlight.current = false; setError(humanizeError(err)) },
    })
  }
  return (
    <Dialog open={open} onOpenChange={(next) => { if (!create.isPending) onOpenChange(next) }}>
      <DialogContent className="lign-warm max-h-[90dvh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>New workspace</DialogTitle>
          <DialogDescription>You remain the owner. Assign a workspace lead and architects to run its projects.</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4">
          {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
          <div className="space-y-1.5"><Label htmlFor="nw-name">Workspace name</Label><Input id="nw-name" autoFocus required maxLength={120} value={name} onChange={(e) => setName(e.target.value)} disabled={create.isPending} placeholder="e.g. Residential studio" /></div>
          {!organizationId && options.length > 1 && <div className="space-y-1.5"><Label htmlFor="nw-org">Studio</Label><select className="auth-field" id="nw-org" value={effectiveOrg ?? ''} disabled={create.isPending} onChange={(e) => { setOrgId(e.target.value); setLead(''); setTeam([]) }}>{options.map((org) => <option key={org.id} value={org.id}>{org.name}</option>)}</select></div>}
          <div className="space-y-1.5">
            <Label htmlFor="nw-lead">Workspace lead</Label>
            <select id="nw-lead" className="auth-field" value={lead} onChange={(e) => { setLead(e.target.value); setTeam((ids) => ids.filter((id) => id !== e.target.value)) }} disabled={create.isPending || members.isLoading}>
              <option value="">Me — lead this workspace initially</option>
              {architects.map((m) => <option key={m.userId} value={m.userId}>{m.name}</option>)}
            </select>
            <p className="text-xs text-[--color-text-muted]">The workspace lead can oversee every project and assign project leads.</p>
          </div>
          <fieldset disabled={create.isPending} className="space-y-2">
            <legend className="text-sm font-medium">Workspace team</legend>
            {members.isLoading ? <p className="text-sm">Loading studio architects…</p> : members.isError ? <p role="alert" className="text-sm text-red-700">Could not load the studio team. Try opening this dialog again.</p> : architects.length === 0 ? <p className="text-sm text-[--color-text-muted]">Invite architects through Studio people. You can assign them here once they have joined.</p> : <div className="max-h-40 space-y-2 overflow-y-auto">{architects.map((m) => <label key={m.userId} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={m.userId === lead || team.includes(m.userId)} disabled={m.userId === lead} onChange={(e) => setTeam((ids) => e.target.checked ? [...ids, m.userId] : ids.filter((id) => id !== m.userId))} />{m.name}{m.userId === lead ? ' · workspace lead' : ''}</label>)}</div>}
          </fieldset>
          <DialogFooter><Button type="button" variant="ghost" disabled={create.isPending} onClick={() => onOpenChange(false)}>Cancel</Button><Button type="submit" disabled={!name.trim() || !effectiveOrg || create.isPending}>{create.isPending ? 'Creating…' : 'Create workspace'}</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
