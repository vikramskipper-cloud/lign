import * as React from 'react'
import { Link, useParams } from 'react-router'
import { Building2, FolderOpen, Users, ClipboardCheck, Stamp, Plus } from 'lucide-react'
import { useStudioOverview } from './queries'
import { NewWorkspaceDialog } from '@/features/workspaces/NewWorkspaceDialog'
import { NewProjectDialog } from '@/features/projects/NewProjectDialog'
import { FullPageLoader } from '@/ui/full-page-loader'
import { relative } from '@/lib/formatDate'

export const OverviewHandle = { crumb: 'Overview' }
const panel: React.CSSProperties = { border: '1px solid var(--panel-border)', background: 'var(--surface)', borderRadius: 12, padding: 20 }
const muted: React.CSSProperties = { color: 'var(--muted)', fontSize: 13, lineHeight: 1.5 }
const button: React.CSSProperties = { display: 'inline-flex', alignItems: 'center', gap: 7, padding: '9px 13px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--surface)', color: 'var(--ink)', cursor: 'pointer', textDecoration: 'none', fontSize: 13 }

export function OverviewScreen() {
  const { org_id: orgId, ws_id: wsId } = useParams<{ org_id?: string; ws_id?: string }>()
  const overview = useStudioOverview(orgId, wsId)
  const [newWorkspace, setNewWorkspace] = React.useState(false)
  const [newProject, setNewProject] = React.useState(false)
  if (overview.isLoading) return <FullPageLoader label="Loading overview" />
  if (overview.isError || !overview.data) return (
    <div className="lign-warm" style={{ padding: 28 }}>
      <h1 className="auth-display" style={{ fontSize: 28 }}>Overview unavailable</h1>
      <p role="alert" style={muted}>This overview is available to the studio owner or the workspace leadership. If you have access, try again.</p>
      <button type="button" style={button} onClick={() => void overview.refetch()}>Try again</button>
      <Link to="/my-work" style={{ ...button, marginLeft: 8 }}>My work</Link>
    </div>
  )
  const data = overview.data
  const projects = data.workspaces.flatMap((w) => w.projects)
  const reviews = projects.reduce((n, p) => n + p.pendingReviews, 0)
  const approvals = projects.reduce((n, p) => n + p.pendingApprovals, 0)
  const title = wsId ? 'Workspace overview' : `${data.organizationName} overview`
  const metrics = [
    { label: 'Workspaces', value: data.workspaces.length, icon: Building2 },
    { label: 'Projects', value: projects.length, icon: FolderOpen },
    { label: 'Open reviews', value: reviews, icon: ClipboardCheck },
    { label: 'Pending approvals', value: approvals, icon: Stamp },
  ]
  return (
    <div className="lign-warm mx-auto w-full max-w-6xl p-5 md:p-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="auth-mono" style={{ ...muted, fontSize: 11, letterSpacing: '.12em' }}>{wsId ? 'WORKSPACE OVERVIEW' : 'STUDIO OVERVIEW'}</p>
          <h1 className="auth-display" style={{ fontSize: 32, lineHeight: 1.15, marginTop: 6 }}>{title}</h1>
          <p style={{ ...muted, marginTop: 8 }}>{wsId ? 'Every project in this workspace, its lead and the work waiting for attention.' : 'Every workspace and project in your studio, including work delegated to other leads.'}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {!wsId&&<Link style={button} to={`/org/${data.organizationId}/settings`}>Organisation settings</Link>}
          {!wsId && <Link style={button} to={`/org/${data.organizationId}/access`}>Access directory</Link>}
          <Link style={button} to={wsId ? `/workspace/${wsId}/people` : `/org/${data.organizationId}/people`}><Users size={15} />{wsId ? 'Manage team' : 'Studio people'}</Link>
          <button type="button" style={{ ...button, background: 'var(--accent)', color: '#fff', borderColor: 'var(--accent)' }} onClick={() => wsId ? setNewProject(true) : setNewWorkspace(true)}><Plus size={15} />{wsId ? 'New project' : 'New workspace'}</button>
        </div>
      </div>
      <div className="my-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {metrics.map(({ label, value, icon: Icon }) => <div key={label} style={panel}><div className="flex items-center gap-2" style={muted}><Icon size={15} />{label}</div><p style={{ fontSize: 30, fontWeight: 600, marginTop: 8 }}>{value}</p></div>)}
      </div>
      <div className="space-y-5">
        {data.workspaces.length === 0 && <p style={panel}>Create your first workspace and assign a workspace lead.</p>}
        {data.workspaces.map((workspace) => (
          <section key={workspace.id} style={panel} aria-label={`${workspace.name} workspace`}>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 style={{ fontSize: 20, fontWeight: 600 }}><Link className="auth-link" to={`/workspace/${workspace.id}/overview`}>{workspace.name}</Link></h2>
                <p style={{ ...muted, marginTop: 5 }}>Workspace lead: {workspace.leads.filter((l) => l.role === 'admin').map((l) => l.name).join(', ') || workspace.leads.map((l) => l.name).join(', ') || 'Not assigned'} · {workspace.teamCount} team members</p>
              </div>
              <Link style={button} to={`/workspace/${workspace.id}/people`}>Manage team</Link>
            </div>
            {workspace.projects.length === 0 ? <p style={{ ...muted, marginTop: 18 }}>No projects yet. <Link className="auth-link" to={`/workspace/${workspace.id}/projects`}>Create the first project</Link>.</p> : (
              <div className="mt-4 grid gap-3 md:grid-cols-2">
                {workspace.projects.map((project) => <article key={project.id} style={{ padding: 15, border: '1px solid var(--row-divider)', borderRadius: 9 }}>
                  <div className="flex flex-wrap items-center justify-between gap-2"><h3 style={{ fontWeight: 600 }}><Link className="auth-link" to={`/workspace/${workspace.id}/project/${project.id}/overview`}>{project.name}</Link></h3><span style={muted}>{project.status.replaceAll('_', ' ')}</span></div>
                  <p style={{ ...muted, marginTop: 7 }}>Project lead: {project.leads.map((l) => l.name).join(', ') || 'Not assigned'}</p>
                  <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1" style={muted}>
                    <Link className="auth-link" to={`/workspace/${workspace.id}/project/${project.id}/reviews`}>{project.pendingReviews} open reviews</Link>
                    <Link className="auth-link" to={`/workspace/${workspace.id}/approvals`}>{project.pendingApprovals} pending approvals</Link>
                  </div>
                  <p style={{ ...muted, fontSize: 12, marginTop: 10 }}>Latest activity {relative(project.latestActivityAt)}</p>
                  <Link className="auth-link" style={{ fontSize: 12 }} to={`/workspace/${workspace.id}/project/${project.id}/people`}>Project team</Link>
                </article>)}
              </div>
            )}
          </section>
        ))}
      </div>
      <section style={{ ...panel, marginTop: 24 }} aria-label="Recent studio activity">
        <h2 style={{ fontSize: 18, fontWeight: 600 }}>Recent activity</h2>
        {data.activity.length === 0 ? <p style={{ ...muted, marginTop: 12 }}>Activity will appear as your team starts work.</p> : <ul className="mt-3 space-y-3">{data.activity.map((event) => <li key={event.id} style={{ ...muted, borderTop: '1px solid var(--row-divider)', paddingTop: 10 }}><strong style={{ color: 'var(--ink)', fontWeight: 500 }}>{event.actor}</strong> · {event.eventType.split('.').slice(1).join(' ').replaceAll('_', ' ')}{event.subject ? ` · ${event.subject}` : ''}<br /><span style={{ fontSize: 12 }}>{event.workspaceName} · {relative(event.occurredAt)}</span></li>)}</ul>}
      </section>
      <NewWorkspaceDialog open={newWorkspace} onOpenChange={setNewWorkspace} organizationId={data.organizationId} />
      {wsId && <NewProjectDialog workspaceId={wsId} open={newProject} onOpenChange={setNewProject} />}
    </div>
  )
}
