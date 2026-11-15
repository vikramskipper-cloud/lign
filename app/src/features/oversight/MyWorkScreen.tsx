import { useState } from 'react'
import { Link } from 'react-router'
import { useOverviewHub } from './hub'
import { AttentionList } from './AttentionList'
import { FeedScope, useFeedScope } from './FeedScope'
import './overview.css'

export function Component() {
  const scope = useFeedScope()
  const query = useOverviewHub(scope.organizationId, scope.workspaceId, true)
  const [search, setSearch] = useState('')
  const [limit, setLimit] = useState(10)
  if (scope.isLoading || query.isLoading) return <p role="status" className="overview-page">Loading your work…</p>
  if (scope.isError || query.isError || !query.data) return <div className="overview-page"><h1>My work</h1><p role="alert">Could not load your work.</p><button className="overview-button" onClick={() => { void scope.refresh(); void query.refetch() }}>Try again</button></div>
  const data = query.data
  const items = [...data.library.map(a => ({ ...a, context: 'Organisation library' })), ...data.projects.flatMap(p => p.summary.actions.map(a => ({ ...a, context: `${p.workspaceName} · ${p.name}` })))]
  const projects = data.projects.filter(p => `${p.name} ${p.workspaceName} ${p.code ?? ''}`.toLowerCase().includes(search.toLowerCase()))
  return <div className="overview-page">
    <header className="overview-heading"><div><p className="overview-eyebrow">{data.organizationName}</p><h1>My work</h1><p className="overview-muted">Your assigned decisions and next steps, across the organisation.</p></div><FeedScope scope={scope}/></header>
    <section className="overview-panel"><div className="overview-section-heading"><h2>Needs your action</h2><span className="overview-small">{items.filter(a => a.canAct).length} items</span></div><AttentionList items={items.filter(a => a.canAct)} empty="No decisions currently need your action in this view."/></section>
    <section className="overview-panel"><h2>Waiting on others</h2><AttentionList items={items.filter(a => !a.canAct)} empty="No outstanding decisions from others in your accessible projects." initialLimit={4}/></section>
    <section className="overview-panel"><div className="overview-section-heading"><h2>Your accessible projects</h2><span className="overview-small">{projects.length} projects</span></div><label className="overview-filters"><span className="sr-only">Find a project</span><input aria-label="Find a project" className="auth-field w-full" type="search" placeholder="Find a project" value={search} onChange={e=>{setSearch(e.target.value);setLimit(10)}}/></label><ul className="overview-action-list">{projects.slice(0,limit).map(p=><li key={p.id}><Link className="overview-action-title" to={`/workspace/${p.workspaceId}/project/${p.id}/overview`}>{p.name} →</Link><p className="overview-small">{p.workspaceName} · {p.summary.phase}</p></li>)}</ul>{!projects.length&&<p className="overview-muted">No projects match this view.</p>}{projects.length>limit&&<button className="auth-link overview-more" onClick={()=>setLimit(n=>n+10)}>Show more projects</button>}</section>
  </div>
}
