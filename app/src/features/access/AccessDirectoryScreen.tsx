import * as React from 'react'
import { Link, useParams } from 'react-router'
import { Badge } from '@/ui/badge'
import { FullPageLoader } from '@/ui/full-page-loader'
import { RoleBadge } from './RoleBadge'
import { useAccessDirectory, type DirectoryPerson } from './directoryQueries'
import { ORG_ROLE_LABELS, ORG_ROLE_DESCRIPTIONS, WORKSPACE_ROLE_LABELS, WORKSPACE_ROLE_DESCRIPTIONS, PROJECT_ROLE_LABELS, PROJECT_ROLE_DESCRIPTIONS } from './roleLabels'
import type { OrgRole } from '@/shell/orgQueries'
import type { ProjectRole, WorkspaceRole } from './queries'
import { relative } from '@/lib/formatDate'

const hasExternalAccess = (person: DirectoryPerson) => !person.internal || person.projectRoles.some((p) => p.source === 'external')
export function AccessDirectoryScreen() {
  const { org_id: orgId } = useParams<{ org_id: string }>()
  const directory = useAccessDirectory(orgId)
  const [search, setSearch] = React.useState('')
  const [kind, setKind] = React.useState('all')
  const [workspaceId, setWorkspaceId] = React.useState('')
  if (directory.isLoading) return <FullPageLoader label="Loading access directory" />
  if (!directory.data || directory.isError) return <div className="p-6"><h1 className="text-xl font-semibold">Access directory unavailable</h1><p role="alert" className="mt-2 text-sm">Only studio owners and administrators can view this directory.</p><button type="button" className="auth-link mt-3" onClick={() => void directory.refetch()}>Try again</button></div>
  const data = directory.data
  const workspaceNames = new Map(data.workspaces.map((w) => [w.id, w.name]))
  const matches = (person: DirectoryPerson) => {
    if (kind === 'internal' && !person.internal || kind === 'external' && !hasExternalAccess(person)) return false
    if (workspaceId && !person.inheritedAdministration && !person.workspaceRoles.some((w) => w.workspaceId === workspaceId) && !person.projectRoles.some((p) => p.workspaceId === workspaceId)) return false
    const terms = [person.name, person.email, person.organizationRole ? ORG_ROLE_LABELS[person.organizationRole] : '', ...person.workspaceRoles.map((w) => WORKSPACE_ROLE_LABELS[w.role]), ...person.projectRoles.map((p) => `${p.projectName} ${PROJECT_ROLE_LABELS[p.role]}`)]
    return terms.join(' ').toLowerCase().includes(search.trim().toLowerCase())
  }
  const people = data.people.filter(matches)
  const invitations = data.pendingInvitations.filter((i) => (!workspaceId || i.workspaceId === workspaceId) && (kind !== 'external' || i.scope === 'external') && (kind !== 'internal' || i.scope !== 'external') && i.email.toLowerCase().includes(search.trim().toLowerCase()))
  return <div className="lign-warm mx-auto w-full max-w-6xl space-y-6 p-5 md:p-7">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h1 className="auth-display text-3xl">Access directory</h1><p className="mt-2 text-sm text-[--color-text-muted]">{data.organizationName} · Internal and external people, assigned roles and inherited access.</p></div>
      <Link className="auth-link text-sm" to={`/org/${orgId}/people`}>Manage studio people</Link>
    </div>
    <p className="text-sm text-[--color-text-muted]">Studio and workspace leadership can administer all projects in their scope. Publishing designs, participating in reviews and responding to approvals depend on project roles and individual assignments.</p>
    <div className="flex flex-wrap items-end gap-3">
      <div className="min-w-0 flex-1"><label htmlFor="directory-search" className="mb-1 block text-sm">Search people or project roles</label><input id="directory-search" className="auth-field" type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Name, email, project or role" /></div>
      <div><label htmlFor="directory-kind" className="mb-1 block text-sm">People</label><select id="directory-kind" className="auth-field" value={kind} onChange={(e) => setKind(e.target.value)}><option value="all">Internal and external</option><option value="internal">Internal people</option><option value="external">External access</option></select></div>
      <div className="max-w-full"><label htmlFor="directory-workspace" className="mb-1 block text-sm">Workspace</label><select id="directory-workspace" className="auth-field max-w-full" value={workspaceId} onChange={(e) => setWorkspaceId(e.target.value)}><option value="">All workspaces</option>{data.workspaces.map((w) => <option key={w.id} value={w.id}>{w.name}{w.status !== 'active' ? ` (${w.status})` : ''}</option>)}</select></div>
    </div>
    <p role="status" className="text-sm">{people.length} people · {invitations.length} pending invitations</p>
    {people.length === 0 && <p className="rounded-xl border border-[--color-border] p-5">No people match these filters.</p>}
    {people.map((person) => {
      const visibleWorkspaces = data.workspaces.filter((w) => (!workspaceId || workspaceId === w.id) && (person.inheritedAdministration || person.workspaceRoles.some((m) => m.workspaceId === w.id) || person.projectRoles.some((p) => p.workspaceId === w.id)))
      return <article key={person.id} aria-label={`Access for ${person.name}`} className="space-y-4 rounded-xl border border-[--color-border] bg-[--color-surface] p-5">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="min-w-0"><h2 className="break-words text-lg font-semibold">{person.name}</h2><p className="break-all text-sm text-[--color-text-muted]">{person.email}</p></div>
          <div className="flex flex-wrap gap-2">{person.internal && <Badge>Internal</Badge>}{hasExternalAccess(person) && <Badge variant="neutral">External{person.internal ? ' project access' : ''}</Badge>}{person.organizationRole && <RoleBadge scope="organization" role={person.organizationRole} />}{person.organizationStatus && person.organizationStatus !== 'active' && <Badge variant="warning">Studio membership {person.organizationStatus}</Badge>}</div>
        </div>
        {person.organizationRole && <p className="text-xs text-[--color-text-muted]">{person.organizationStatus === 'active' ? ORG_ROLE_DESCRIPTIONS[person.organizationRole] : 'This studio membership is inactive. Any workspace or project assignments shown below are separate.'}</p>}
        {person.inheritedAdministration && <p className="rounded-lg bg-[--color-surface-2] p-3 text-sm">Inherited administration: every workspace and project in this studio. Project roles below show their additional design-work permissions.</p>}
        {visibleWorkspaces.length === 0 && <p className="text-sm text-[--color-text-muted]">No workspace or project assignments.</p>}
        {visibleWorkspaces.map((workspace) => {
          const membership = person.workspaceRoles.find((m) => m.workspaceId === workspace.id)
          const projects = person.projectRoles.filter((p) => p.workspaceId === workspace.id)
          return <section key={workspace.id} className="space-y-2 border-t border-[--color-border] pt-3" aria-label={`${workspace.name} access`}>
            <div className="flex flex-wrap items-center gap-2"><Link className="auth-link font-medium" to={`/workspace/${workspace.id}/people`}>{workspace.name}</Link>{workspace.status !== 'active' && <Badge variant="outline">{workspace.status}</Badge>}{membership ? <><RoleBadge scope="workspace" role={membership.role} />{membership.status !== 'active' && <Badge variant="warning">{membership.status}</Badge>}</> : <Badge variant="outline">{person.inheritedAdministration ? 'Inherited studio administration' : 'Project access only'}</Badge>}</div>
            {membership && <p className="text-xs text-[--color-text-muted]">{membership.status === 'active' ? WORKSPACE_ROLE_DESCRIPTIONS[membership.role] : 'Workspace membership is not active.'}</p>}
            {projects.length === 0 && <p className="text-xs text-[--color-text-muted]">No assigned project roles.{person.inheritedAdministration || membership?.status === 'active' && membership.role !== 'member' ? ' Administrative access still includes every project here.' : ''}</p>}
            {projects.map((p) => <div key={p.id} className="space-y-1 rounded-lg bg-[--color-surface-2] p-3"><div className="flex flex-wrap items-center gap-2"><Link className="auth-link text-sm" to={`/workspace/${p.workspaceId}/project/${p.projectId}/people`}>{p.projectName}</Link><RoleBadge scope="project" role={p.role} />{p.source === 'external' && <Badge>External</Badge>}{p.status !== 'active' && <Badge variant="warning">Invitation not yet accepted</Badge>}{p.archived && <Badge variant="outline">Archived project</Badge>}</div><p className="text-xs text-[--color-text-muted]">{PROJECT_ROLE_DESCRIPTIONS[p.role]}</p></div>)}
          </section>
        })}
      </article>
    })}
    <section className="space-y-3" aria-label="Pending access invitations"><h2 className="text-lg font-semibold">Pending invitations</h2><p className="text-sm text-[--color-text-muted]">These invitations have not been accepted and do not confirm active access.</p>{invitations.length === 0 && <p className="text-sm">No pending invitations match these filters.</p>}{invitations.map((i) => <div key={i.id} className="flex flex-wrap items-center gap-2 rounded-lg border border-[--color-border] p-3"><span className="min-w-0 break-all text-sm">{i.email}</span><Badge variant="warning">Pending</Badge>{i.scope === 'organization' ? <RoleBadge scope="organization" role={i.role as OrgRole} /> : i.scope === 'workspace' ? <RoleBadge scope="workspace" role={i.role as WorkspaceRole} /> : <><Badge>External</Badge><RoleBadge scope="project" role={i.role as ProjectRole} /></>}<span className="text-xs text-[--color-text-muted]">{i.workspaceId ? workspaceNames.get(i.workspaceId) : data.organizationName} · expires {relative(i.expiresAt)}</span></div>)}</section>
  </div>
}
