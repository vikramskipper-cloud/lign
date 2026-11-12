import * as React from 'react'
import { useParams } from 'react-router'
import { UserPlus, X } from 'lucide-react'
import { Button } from '@/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { Badge } from '@/ui/badge'
import { Avatar, AvatarFallback } from '@/ui/avatar'
import { EmptyState } from '@/ui/empty-state'
import { AsyncBoundary } from '@/ui/async-boundary'
import { Skeleton } from '@/ui/skeleton'
import { useCapability, useWorkspaceAccess } from '@/lib/capabilities'
import { PROJECT_ROLE_LABELS, PROJECT_ROLE_DESCRIPTIONS } from './roleLabels'
import { RoleBadge } from './RoleBadge'
import { InviteDialog } from './InviteDialog'
import {
  PROJECT_ROLES,
  useAssignableMembers,
  useProjectAccess,
  type ProjectRole,
} from './queries'
import {
  useAddParticipant,
  useChangeParticipantRole,
  useRemoveParticipant,
} from './mutations'

const ParticipantAccessEditor = React.lazy(() => import('./ParticipantAccessEditor').then(m => ({ default: m.ParticipantAccessEditor })))

function initials(s: string) {
  return s.slice(0, 2).toUpperCase()
}

export function ProjectPeopleScreen() {
  const { ws_id: wsId, proj_id: projId } = useParams<{ ws_id: string; proj_id: string }>()
  const [inviteOpen, setInviteOpen] = React.useState(false)
  const [addMemberId, setAddMemberId] = React.useState('')
  const [addRole, setAddRole] = React.useState<ProjectRole>('contributor')

  const canManage = useCapability(projId, wsId, 'project.manage_access')
  const wsAccess = useWorkspaceAccess(wsId)
  const canInviteStakeholder = canManage
  const externalRoles: ProjectRole[] = wsAccess.data?.['stakeholder.invite']
    ? [...PROJECT_ROLES] : ['reviewer', 'approver']

  const participants = useProjectAccess(projId)
  const assignable = useAssignableMembers(wsId, projId)

  const addParticipant = useAddParticipant(wsId ?? '', projId ?? '')
  const changeRole = useChangeParticipantRole(wsId ?? '', projId ?? '')
  const removeParticipant = useRemoveParticipant(wsId ?? '', projId ?? '')

  const rows = participants.data ?? []
  const candidates = assignable.data ?? []

  const add = (e: React.FormEvent) => {
    e.preventDefault()
    if (!addMemberId) return
    addParticipant.mutate(
      { workspaceMemberId: addMemberId, role: addRole },
      { onSuccess: () => setAddMemberId('') },
    )
  }

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6 p-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold">Project people</h1>
          <p className="mt-1 text-sm text-[--color-text-muted]">
            Participation is what grants access to this project. Workspace admins can view it
            without appearing here.
          </p>
        </div>
        {canInviteStakeholder && (
          <Button variant="secondary" onClick={() => setInviteOpen(true)}>
            <UserPlus className="mr-1.5 h-4 w-4" />
            Invite external
          </Button>
        )}
      </div>

      <AsyncBoundary>
        {canManage && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Add a workspace member</CardTitle>
              <CardDescription>
                {candidates.length === 0
                  ? 'Everyone in the workspace is already on this project.'
                  : `${candidates.length} available`}
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={add} className="flex flex-wrap items-end gap-2">
                <select
                  aria-label="Workspace member"
                  className="h-9 min-w-[16rem] flex-1 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-2 text-sm"
                  value={addMemberId}
                  disabled={candidates.length === 0 || addParticipant.isPending}
                  onChange={(e) => setAddMemberId(e.target.value)}
                >
                  <option value="">Select someone…</option>
                  {candidates.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.displayName} ({m.email})
                    </option>
                  ))}
                </select>
                <select
                  aria-label="Project role"
                  className="h-9 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-2 text-sm"
                  value={addRole}
                  disabled={addParticipant.isPending}
                  onChange={(e) => setAddRole(e.target.value as ProjectRole)}
                >
                  {PROJECT_ROLES.map((r) => (
                    <option key={r} value={r}>
                      {PROJECT_ROLE_LABELS[r]}
                    </option>
                  ))}
                </select>
                <Button type="submit" disabled={!addMemberId || addParticipant.isPending}>
                  Add
                </Button>
              </form>
            </CardContent>
          </Card>
        )}

        <p className="mt-4 text-sm text-[--color-text-muted]">Every project keeps at least one project lead. Assign the next lead before handing over or removing the current lead.</p>
        <Card className="mt-6">
          <CardHeader>
            <CardTitle className="text-base">Participants</CardTitle>
            <CardDescription>{rows.length} on this project</CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {participants.isLoading && <Skeleton className="h-10 w-full" />}
            {!participants.isLoading && rows.length === 0 && (
              <EmptyState
                title="Nobody on this project yet"
                description="Add a workspace member, or invite an external stakeholder."
              />
            )}
            {rows.map((p) => (
              <div
                key={p.id}
                className="flex flex-wrap items-center gap-3 rounded-[--radius-md] px-2 py-2 hover:bg-[--color-surface-2]"
              >
                <Avatar className="h-8 w-8">
                  <AvatarFallback>{initials(p.displayName)}</AvatarFallback>
                </Avatar>
                <div className="min-w-0 flex-1 basis-52">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="truncate text-sm font-medium">{p.displayName}</span>
                    <RoleBadge scope="project" role={p.role} />
                    {p.professionalLabel && <Badge className="max-w-full break-all">Professional: {p.professionalLabel}</Badge>}
                    {p.canSubmitDeliverables && <Badge>Can submit deliverables</Badge>}
                    <Badge variant="neutral">{p.kind === 'stakeholder' ? 'External' : 'Internal'}</Badge>
                    {p.pending && <Badge variant="outline">Invitation not yet accepted</Badge>}
                  </div>
                  <div className="truncate text-xs text-[--color-text-muted]">{p.email}</div>
                  <p className="mt-1 text-xs text-[--color-text-muted]">{PROJECT_ROLE_DESCRIPTIONS[p.role]}</p>
                  {p.canSubmitDeliverables && <p className="mt-1 text-xs text-[--color-text-muted]">Can submit their own draft deliverables for team review.</p>}
                  {canManage && <React.Suspense fallback={<p className="text-xs">Loading access settings…</p>}><ParticipantAccessEditor person={p} workspaceId={wsId ?? ''} projectId={projId ?? ''} /></React.Suspense>}
                </div>

                {canManage ? (
                  <select
                    aria-label={`Role for ${p.displayName}`}
                    className="h-8 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-2 text-xs"
                    value={p.role}
                    disabled={changeRole.isPending}
                    onChange={(e) =>
                      changeRole.mutate({
                        participantId: p.id,
                        role: e.target.value as ProjectRole,
                      })
                    }
                  >
                    {PROJECT_ROLES.map((r) => (
                      <option key={r} value={r}>
                        {PROJECT_ROLE_LABELS[r]}
                      </option>
                    ))}
                  </select>
                ) : null}

                {canManage && (
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Remove ${p.displayName}`}
                    disabled={removeParticipant.isPending}
                    onClick={() => {
                      if (
                        window.confirm(
                          `Remove ${p.displayName} from this project? Their past work stays attributed to them.`,
                        )
                      ) {
                        removeParticipant.mutate(p.id)
                      }
                    }}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      </AsyncBoundary>

      {wsId && projId && (
        <InviteDialog
          open={inviteOpen}
          onOpenChange={setInviteOpen}
          workspaceId={wsId}
          mode="stakeholder"
          projectId={projId}
          allowedProjectRoles={externalRoles}
        />
      )}
    </div>
  )
}

ProjectPeopleScreen.handle = { crumb: 'People' }
