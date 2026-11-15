import { lazy, Suspense, useState } from 'react'
import { Link, useParams } from 'react-router'
import { useWorkspace } from '@/shell/queries'
import { FullPageLoader } from '@/ui/full-page-loader'
import { useOverviewHub, activityLabel, type AttentionItem } from './hub'
import { AttentionList } from './AttentionList'
import { relative } from '@/lib/formatDate'
import './overview.css'

const NewWorkspaceDialog = lazy(() => import('@/features/workspaces/NewWorkspaceDialog').then(m => ({ default: m.NewWorkspaceDialog })))
const NewProjectDialog = lazy(() => import('@/features/projects/NewProjectDialog').then(m => ({ default: m.NewProjectDialog })))
export const OverviewHandle = { crumb: 'Overview' }

export function OverviewScreen() {
  const { org_id, ws_id } = useParams()
  const workspace = useWorkspace(ws_id)
  const overview = useOverviewHub(org_id ?? workspace.data?.organization_id, ws_id)
  const [creating, setCreating] = useState(false)
  const [search, setSearch] = useState('')
  const [phase, setPhase] = useState('all')
  const [scope, setScope] = useState('all')
  const [attention, setAttention] = useState('all')
  const [limit, setLimit] = useState(15)
  if (overview.isLoading || (ws_id && workspace.isLoading)) return <FullPageLoader label="Loading overview" />
  if (overview.isError || workspace.isError || !overview.data) return <div className="overview-page"><h1>Overview unavailable</h1><p role="alert">This overview requires organisation or workspace leadership access.</p><button className="overview-button" onClick={() => { void overview.refetch(); if (ws_id) void workspace.refetch() }}>Try again</button><Link className="auth-link" to="/my-work">Open My work</Link></div>
  const data = overview.data
  const actions = [...data.library.map(a => ({ ...a, context: 'Organisation library' })), ...data.projects.flatMap(p => p.summary.actions.map(a => ({ ...a, context: `${p.workspaceName} · ${p.name}` }))) ]
  const matchesAttention = (a: AttentionItem) => attention === 'all' || (attention === 'mine' ? a.canAct : attention === 'client' ? a.audience === 'client' && !a.canAct : !a.canAct && a.audience !== 'client')
  const projects = data.projects.filter(p => (scope === 'all' || p.workspaceId === scope) && (phase === 'all' || p.summary.phase === phase)
    && (attention === 'all' || p.summary.actions.some(matchesAttention))
    && `${p.name} ${p.code ?? ''} ${p.workspaceName} ${p.summary.lead}`.toLowerCase().includes(search.toLowerCase()))
  const activity = data.projects.flatMap(p => p.summary.activity.map(e => ({ ...e, project: p }))).sort((a,b) => b.at.localeCompare(a.at)).slice(0,5)
  const metric = (label: string, count: number, filter: string) => <a href="#attention" onClick={() => setAttention(filter)}><strong>{count}</strong>{label}</a>
  return <div className="overview-page">
    <header className="overview-heading"><div><p className="overview-eyebrow">{ws_id ? 'Workspace' : 'Organisation'} overview</p><h1>{ws_id ? workspace.data?.name : data.organizationName}</h1><p className="overview-muted">{ws_id ? 'Move team decisions forward and see where each project stands.' : 'See where your studio needs attention, across every workspace.'}</p></div><div className="flex flex-wrap gap-2">
      {!ws_id && <Link className="overview-button" to={`/org/${data.organizationId}/settings`}>Organisation settings</Link>}
      <button className="overview-button overview-primary" onClick={() => setCreating(true)}>{ws_id ? 'New project' : 'New workspace'}</button>
    </div></header>
    <div className="overview-metrics" aria-label="Attention summary">{metric('Needs your action', actions.filter(a=>a.canAct).length, 'mine')}{metric('Waiting on approvers', actions.filter(a=>!a.canAct && a.audience==='client').length, 'client')}{metric('Needs team / reviewers', actions.filter(a=>!a.canAct && a.audience!=='client').length, 'team')}<a href="#portfolio"><strong>{data.projects.length}</strong>Projects · {data.workspaces.length} {ws_id ? 'workspace' : 'workspaces'}</a></div>
    <section id="attention" className="overview-panel"><div className="overview-section-heading"><h2>{ws_id ? 'Team action queue' : 'Decisions & next steps'}</h2><label className="overview-small">Show <select className="auth-field ml-2" aria-label="Attention filter" value={attention} onChange={e=>{setAttention(e.target.value);setLimit(15)}}><option value="all">All next steps</option><option value="mine">Needs your action</option><option value="client">Waiting on approvers</option><option value="team">Needs team / reviewers</option></select></label></div><AttentionList items={actions.filter(matchesAttention)} initialLimit={4} empty="No pending items in this view." /></section>
    {!ws_id && <section aria-label="Workspace summaries"><div className="overview-section-heading mb-3"><h2>Workspaces</h2><Link className="auth-link text-sm" to={`/workspaces?org=${data.organizationId}`}>View directory</Link></div><div className="overview-grid">{data.workspaces.map(w=>{const list=data.projects.filter(p=>p.workspaceId===w.id);return <article key={w.id} className="overview-panel overview-workspace"><Link to={`/workspace/${w.id}/overview`}>{w.name} →</Link><p className="overview-muted">Lead: {w.lead ?? 'Not assigned'}</p><p className="overview-small">{list.length} projects · {list.reduce((n,p)=>n+p.summary.actions.length,0)} pending next steps</p></article>})}</div>{!data.workspaces.length&&<p className="overview-panel overview-muted">Create your first workspace to begin.</p>}</section>}
    <section id="portfolio" className="overview-panel"><h2>Project portfolio</h2><div className="overview-filters">
      <label>Find a project<input className="auth-field" type="search" placeholder="Project, code or lead" value={search} onChange={e=>{setSearch(e.target.value);setLimit(15)}} /></label>
      {!ws_id && <label>Workspace<select className="auth-field" value={scope} onChange={e=>{setScope(e.target.value);setLimit(15)}}><option value="all">All workspaces</option>{data.workspaces.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label>}
      <label>Project phase<select className="auth-field" value={phase} onChange={e=>{setPhase(e.target.value);setLimit(15)}}><option value="all">All phases</option>{['Requirements & references','Design proposal','Detailed design'].map(p=><option key={p}>{p}</option>)}</select></label>
    </div><p className="overview-small">{projects.length} matching projects{attention !== 'all' ? ' · attention filter applied' : ''}</p>
    <div className="overview-table-wrap"><table className="overview-table"><thead><tr><th scope="col">Project / lead</th><th scope="col">Workspace</th><th scope="col">Phase</th><th scope="col">Next step</th></tr></thead><tbody>{projects.slice(0,limit).map(p=>{const next=[...p.summary.actions].sort((a,b)=>Number(b.canAct)-Number(a.canAct)||a.since.localeCompare(b.since))[0];return <tr key={p.id}><td><Link to={`/workspace/${p.workspaceId}/project/${p.id}/overview`}>{p.name}</Link><p>{p.summary.lead}{p.code ? ` · ${p.code}` : ''}</p></td><td>{p.workspaceName}</td><td>{p.summary.phase}</td><td>{next?<><Link to={next.to}>{next.title}</Link><p>{next.responsible} · {relative(next.since)}</p></>:<span className="overview-muted">No pending decisions</span>}</td></tr>})}</tbody></table></div>
    {!projects.length && <p className="overview-muted">No projects match these filters.</p>}{projects.length>limit&&<button className="auth-link overview-more" onClick={()=>setLimit(n=>n+15)}>Show more projects</button>}</section>
    <section className="overview-panel"><h2>Recent project updates</h2><ul className="overview-action-list">{activity.map(e=><li key={e.id}><Link className="overview-action-title" to={`/workspace/${e.project.workspaceId}/project/${e.project.id}/overview`}>{e.project.name}</Link><p className="overview-muted">{e.actor} · {activityLabel(e.eventType)}{e.subject ? ` · ${e.subject}` : ''}</p><p className="overview-small">{e.project.workspaceName} · {relative(e.at)}</p></li>)}</ul>{!activity.length&&<p className="overview-muted">Updates will appear as your team starts work.</p>}</section>
    {creating&&<Suspense fallback={<p role="status">Loading creation form…</p>}>{ws_id?<NewProjectDialog workspaceId={ws_id} open={creating} onOpenChange={setCreating}/>:<NewWorkspaceDialog organizationId={data.organizationId} open={creating} onOpenChange={setCreating}/>}</Suspense>}
  </div>
}
