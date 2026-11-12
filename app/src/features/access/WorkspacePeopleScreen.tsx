import * as React from 'react'
import { Link, useParams } from 'react-router'
import { Mail, UserPlus, X } from 'lucide-react'
import { Button } from '@/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { Badge } from '@/ui/badge'
import { Avatar, AvatarFallback } from '@/ui/avatar'
import { EmptyState } from '@/ui/empty-state'
import { AsyncBoundary } from '@/ui/async-boundary'
import { Skeleton } from '@/ui/skeleton'
import { useMyOrganizations } from '@/shell/orgQueries'
import { useWorkspace } from '@/shell/queries'
import { WorkspaceTeamAssignment } from './WorkspaceTeamAssignment'
import { WORKSPACE_ROLE_LABELS, WORKSPACE_ROLE_DESCRIPTIONS, PROJECT_ROLE_LABELS } from './roleLabels'
import { RoleBadge } from './RoleBadge'
import { useAccessDirectory } from './directoryQueries'
import { useSession } from '@/auth/SessionProvider'
import { useWorkspaceAccess } from '@/lib/capabilities'
import { relative } from '@/lib/formatDate'
import { InviteDialog } from './InviteDialog'
import {
  WORKSPACE_ROLES,
  useWorkspaceInvitations,
  useWorkspacePeople,
  type WorkspaceRole,
} from './queries'
import { useChangeMemberRole, useRemoveMember, useRevokeInvitation, useRevokeStakeholder } from './mutations'

function initials(s: string) {
  return s.slice(0, 2).toUpperCase()
}

function ExternalProjectAccess({ directory, stakeholderId, workspaceId }: {
  directory: ReturnType<typeof useAccessDirectory>; stakeholderId: string; workspaceId: string
}) {
  if (directory.isLoading) return <p className="text-xs">Loading project access…</p>
  if (directory.isError) return <p role="alert" className="text-xs">Project access unavailable. <button type="button" className="auth-link" onClick={() => void directory.refetch()}>Try again</button></p>
  const projects = directory.data?.people.flatMap((p) => p.projectRoles).filter((p) => p.source === 'external' && p.sourceId === stakeholderId) ?? []
  return projects.length ? <>{projects.map((p) => <div key={p.id} className="flex flex-wrap items-center gap-2"><Link className="auth-link text-xs" to={`/workspace/${workspaceId}/project/${p.projectId}/people`}>{p.projectName}</Link><RoleBadge scope="project" role={p.role} />{p.professionalLabel && <Badge className="max-w-full break-all">Professional: {p.professionalLabel}</Badge>}{p.canSubmitDeliverables && <Badge>Can submit deliverables</Badge>}{p.archived && <Badge variant="outline">Archived</Badge>}</div>)}</> : <p className="text-xs text-[--color-text-muted]">No current project assignments.</p>
}

export function WorkspacePeopleScreen() {
  const { ws_id: wsId } = useParams<{ ws_id: string }>()
  const { user } = useSession()
  const workspace = useWorkspace(wsId)
  const orgs = useMyOrganizations()
  const [inviteOpen, setInviteOpen] = React.useState(false)

  const access = useWorkspaceAccess(wsId)
  const people = useWorkspacePeople(wsId)
  const invitations = useWorkspaceInvitations(wsId)

  const changeRole = useChangeMemberRole(wsId ?? '')
  const removeMember = useRemoveMember(wsId ?? '')
  const revokeStakeholder = useRevokeStakeholder(wsId ?? '')
  const revokeInvite = useRevokeInvitation(wsId ?? '')

  const canInvite = Boolean(access.data?.['member.invite'])
  const canChangeRole = Boolean(access.data?.['member.change_role'])
  const canRemove = Boolean(access.data?.['member.remove'])
  const canRevokeStakeholder = Boolean(access.data?.['stakeholder.revoke'])
  const directory = useAccessDirectory(undefined, wsId, canRevokeStakeholder)

  const members = people.data?.members ?? []
  const stakeholders = people.data?.stakeholders ?? []
  const pending = invitations.data ?? []
  const orgRole = orgs.data?.find((o) => o.id === workspace.data?.organization_id)?.role
  const canAppointLead = orgRole === 'owner' || orgRole === 'admin'
  const canGrantOwner = orgRole === 'owner' || members.some((m) => m.profileId === user?.id && m.role === 'owner' && m.status === 'active')

  // The workspace has no owner if the fixtures (or a direct insert) never made
  // one. Surfaced rather than hidden: only an owner can grant the owner role,
  // so this state cannot be repaired from the UI.
  const hasOwner = members.some((m) => m.role === 'owner' && m.status === 'active')

  return (
    <div className="mx-auto w-full max-w-4xl space-y-6 p-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold">People</h1>
          <p className="mt-1 text-sm text-[--color-text-muted]">
            Workspace members belong to the organisation. Stakeholders are external and only ever
            see the projects they are added to.
          </p>
        </div>
        {canInvite && (
          <Button onClick={() => setInviteOpen(true)}>
            <UserPlus className="mr-1.5 h-4 w-4" />
            Invite member
          </Button>
        )}
      </div>

      {!hasOwner && members.length > 0 && (
        <div className="rounded-[--radius-md] border border-[--color-warning] bg-[--color-surface-2] p-3 text-sm">
          <strong className="font-medium">This workspace has no owner.</strong>{' '}
          <span className="text-[--color-text-muted]">
            Only an owner can grant the owner role, so it cannot be assigned from here. A
            bootstrap path is tracked as APP 013 G-7.
          </span>
        </div>
      )}

      <AsyncBoundary>
        {canInvite && workspace.data && <WorkspaceTeamAssignment workspaceId={wsId ?? ''} organizationId={workspace.data.organization_id} assignedUserIds={members.filter((m) => m.status === 'active').map((m) => m.profileId)} canAppointLead={canAppointLead} />}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Members</CardTitle>
            <CardDescription>{members.length} in this workspace</CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {people.isLoading && <Skeleton className="h-10 w-full" />}
            {!people.isLoading && members.length === 0 && (
              <EmptyState title="No members yet" description="Invite someone to get started." />
            )}
            {members.map((m) => {
              const isSelf = m.profileId === user?.id
              return (
                <div
                  key={m.id}
                  className="flex flex-wrap items-center gap-3 rounded-[--radius-md] px-2 py-2 hover:bg-[--color-surface-2]"
                >
                  <Avatar className="h-8 w-8">
                    <AvatarFallback>{initials(m.displayName)}</AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 flex-1 basis-52">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="truncate text-sm font-medium">{m.displayName}</span>
                      <RoleBadge scope="workspace" role={m.role} />
                      <Badge>Internal</Badge>
                      {isSelf && <Badge variant="brand">you</Badge>}
                      {m.status !== 'active' && <Badge variant="outline">{m.status}</Badge>}
                    </div>
                    <div className="truncate text-xs text-[--color-text-muted]">{m.email}</div>
                    <p className="mt-1 text-xs text-[--color-text-muted]">{WORKSPACE_ROLE_DESCRIPTIONS[m.role]}</p>
                  </div>

                  {canChangeRole && !isSelf ? (
                    <select
                      aria-label={`Role for ${m.displayName}`}
                      className="h-8 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-2 text-xs"
                      value={m.role}
                      disabled={changeRole.isPending || (m.role === 'owner' && !canGrantOwner) || (m.role === 'admin' && !canAppointLead)}
                      onChange={(e) =>
                        changeRole.mutate({
                          memberId: m.id,
                          role: e.target.value as WorkspaceRole,
                        })
                      }
                    >
                      {WORKSPACE_ROLES.filter((r) => r === m.role || r === 'member' || (r === 'admin' && canAppointLead) || (r === 'owner' && canGrantOwner)).map((r) => (
                        <option key={r} value={r}>
                          {WORKSPACE_ROLE_LABELS[r]}
                        </option>
                      ))}
                    </select>
                  ) : null}

                  {canRemove && !isSelf && (
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={`Remove ${m.displayName}`}
                      disabled={removeMember.isPending || (m.role === 'owner' && !canGrantOwner) || (m.role === 'admin' && !canAppointLead)}
                      onClick={() => {
                        if (
                          window.confirm(
                            `Remove ${m.displayName} from the workspace? They lose access to every project in it. Their past work stays attributed to them.`,
                          )
                        ) {
                          removeMember.mutate(m.id)
                        }
                      }}
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              )
            })}
          </CardContent>
        </Card>

        <Card className="mt-6">
          <CardHeader>
            <CardTitle className="text-base">Stakeholders</CardTitle>
            <CardDescription>
              External people, scoped to specific projects. Invite them from a project&apos;s People
              tab.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {stakeholders.length === 0 && (
              <EmptyState
                title="No stakeholders"
                description="External reviewers and approvers appear here once invited from a project."
              />
            )}
            {stakeholders.map((s) => (
              <div
                key={s.id}
                className="flex flex-wrap items-center gap-3 rounded-[--radius-md] px-2 py-2 hover:bg-[--color-surface-2]"
              >
                <Avatar className="h-8 w-8">
                  <AvatarFallback>{initials(s.displayName ?? s.email)}</AvatarFallback>
                </Avatar>
                <div className="min-w-0 flex-1 basis-52">
                  <div className="truncate text-sm font-medium">{s.displayName ?? s.email}</div>
                  <div className="truncate text-xs text-[--color-text-muted]">{s.email}</div>
                  <Badge>External</Badge>
                  {canRevokeStakeholder && <div className="mt-2 space-y-2">
                    <ExternalProjectAccess directory={directory} stakeholderId={s.id} workspaceId={wsId ?? ''} />
                  </div>}
                </div>
                {s.claimedProfileId && s.status === 'active' ? (
                  <Badge variant="success">Active</Badge>
                ) : (
                  <Badge variant="outline">Invitation not yet accepted</Badge>
                )}
                {canRevokeStakeholder && (
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Revoke ${s.email}`}
                    disabled={revokeStakeholder.isPending}
                    onClick={() => {
                      if (
                        window.confirm(
                          `Revoke access for ${s.email}? They are removed from every project in this workspace.`,
                        )
                      ) {
                        revokeStakeholder.mutate(s.id)
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

        {pending.length > 0 && (
          <Card className="mt-6">
            <CardHeader>
              <CardTitle className="text-base">Pending invitations</CardTitle>
              <CardDescription>
                Links already issued. The link itself cannot be shown again — revoke and re-invite
                if it was lost.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-1">
              {pending.map((i) => (
                <div
                  key={i.id}
                  className="flex flex-wrap items-center gap-3 rounded-[--radius-md] px-2 py-2 hover:bg-[--color-surface-2]"
                >
                  <Mail className="h-4 w-4 shrink-0 text-[--color-text-subtle]" />
                  <div className="min-w-0 flex-1 basis-52">
                    <div className="truncate text-sm">{i.email}</div>
                    <div className="truncate text-xs text-[--color-text-muted]">
                      {i.kind === 'stakeholder' ? 'External' : 'Internal'}
                      {i.role ? ` · ${i.kind === 'stakeholder' ? PROJECT_ROLE_LABELS[i.role as keyof typeof PROJECT_ROLE_LABELS] : WORKSPACE_ROLE_LABELS[i.role as WorkspaceRole]}` : ''} · expires {relative(i.expiresAt)}
                      {i.invitedByName ? ` · invited by ${i.invitedByName}` : ''}
                    </div>
                  </div>
                  {canInvite && (
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={revokeInvite.isPending}
                      onClick={() => revokeInvite.mutate(i.id)}
                    >
                      Revoke
                    </Button>
                  )}
                </div>
              ))}
            </CardContent>
          </Card>
        )}
      </AsyncBoundary>

      {wsId && (
        <InviteDialog
          open={inviteOpen}
          onOpenChange={setInviteOpen}
          workspaceId={wsId}
          mode="member" allowedWorkspaceRoles={WORKSPACE_ROLES.filter((r) => r === 'member' || (r === 'admin' && canAppointLead) || (r === 'owner' && canGrantOwner))}
        />
      )}
    </div>
  )
}

WorkspacePeopleScreen.handle = { crumb: 'People' }
