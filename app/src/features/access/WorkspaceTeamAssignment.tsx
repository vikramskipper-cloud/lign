import * as React from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useOrgMembers } from '@/shell/orgQueries'
import { supabase } from '@/lib/supabase'
import { invalidateAccess } from '@/features/shared/invalidate'
import { humanizeError } from '@/features/shared/errors'
import { Button } from '@/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/ui/card'
import { WORKSPACE_ROLE_LABELS } from './roleLabels'

interface Props { workspaceId: string; organizationId: string; assignedUserIds: string[]; canAppointLead: boolean }
export function WorkspaceTeamAssignment({ workspaceId, organizationId, assignedUserIds, canAppointLead }: Props) {
  const members = useOrgMembers(organizationId)
  const qc = useQueryClient()
  const [userId, setUserId] = React.useState('')
  const [role, setRole] = React.useState<'member' | 'admin'>('member')
  const assign = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc('assign_workspace_architect', { p_workspace_id: workspaceId, p_user_id: userId, p_role: role })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success(role === 'admin' ? 'Workspace lead assigned' : 'Architect added to workspace')
      setUserId('')
      invalidateAccess(qc, workspaceId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
  const candidates = (members.data ?? []).filter((m) => m.status === 'active' && !assignedUserIds.includes(m.userId))
  return <Card>
    <CardHeader><CardTitle className="text-base">Add a studio architect</CardTitle><CardDescription>Assign people who have already joined your studio. Project teams are assigned separately.</CardDescription></CardHeader>
    <CardContent>
      {members.isError ? <p role="alert" className="text-sm text-red-700">Could not load studio architects. <button type="button" className="auth-link" onClick={() => void members.refetch()}>Try again</button></p> : <form className="flex flex-wrap items-end gap-3" onSubmit={(event) => { event.preventDefault(); if (userId && !assign.isPending) assign.mutate() }}>
        <div className="min-w-0 flex-1 space-y-1.5"><label htmlFor="assign-architect" className="text-sm font-medium">Architect</label><select id="assign-architect" className="auth-field" value={userId} onChange={(e) => setUserId(e.target.value)} disabled={assign.isPending || members.isLoading}><option value="">{members.isLoading ? 'Loading…' : candidates.length ? 'Choose an architect' : 'Everyone in the studio is already assigned'}</option>{candidates.map((m) => <option key={m.userId} value={m.userId}>{m.name} ({m.email})</option>)}</select></div>
        <div className="space-y-1.5"><label htmlFor="assign-workspace-role" className="text-sm font-medium">Workspace role</label><select id="assign-workspace-role" className="auth-field" value={role} onChange={(e) => setRole(e.target.value as 'member' | 'admin')} disabled={assign.isPending}><option value="member">{WORKSPACE_ROLE_LABELS.member}</option>{canAppointLead && <option value="admin">{WORKSPACE_ROLE_LABELS.admin}</option>}</select></div>
        <Button type="submit" disabled={!userId || assign.isPending}>{assign.isPending ? 'Adding…' : 'Add to workspace'}</Button>
      </form>}
    </CardContent>
  </Card>
}
