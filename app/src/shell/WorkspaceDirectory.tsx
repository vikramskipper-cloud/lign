import {lazy,Suspense,useState} from 'react'
import {Link} from 'react-router'
import {Building2,Plus} from 'lucide-react'
import {useNavigationContext} from './navigationContext'
const NewWorkspaceDialog=lazy(()=>import('@/features/workspaces/NewWorkspaceDialog').then(m=>({default:m.NewWorkspaceDialog})))
export function Component(){
 const context=useNavigationContext(),[search,setSearch]=useState(''),[creating,setCreating]=useState(false)
 const workspaces=context.workspaces.filter(w=>(!context.organizationId||w.organization_id===context.organizationId)&&w.name.toLowerCase().includes(search.trim().toLowerCase()))
 if(context.isLoading)return <p role="status" className="p-6">Loading workspaces…</p>
 if(context.isError)return <div className="p-6"><p role="alert">Could not load workspaces.</p><button className="auth-link" onClick={()=>void context.refresh()}>Retry</button></div>
 return <div className="workspace-directory"><div className="directory-title"><div><p className="context-eyebrow">{context.organizationName}</p><h1>Workspaces</h1><p>Choose a workspace to see its projects and team.</p></div>{context.isAdmin&&<button className="context-primary-action" onClick={()=>setCreating(true)}><Plus size={16}/>New workspace</button>}</div><label className="directory-search">Find a workspace<input className="auth-field" type="search" placeholder="Search workspace names" value={search} onChange={e=>setSearch(e.target.value)}/></label><div className="workspace-directory-grid">{workspaces.map(w=><Link key={w.id} to={`/workspace/${w.id}/projects`} className="workspace-directory-card"><Building2 size={21} aria-hidden="true"/><h2>{w.name}</h2><p>Projects, work queue and workspace team</p><span>Open workspace →</span></Link>)}</div>{!workspaces.length&&<p className="directory-empty">{search.trim()?'No workspaces match your search.':'No workspaces available here yet.'}</p>}{creating&&<Suspense fallback={<p>Loading workspace form…</p>}><NewWorkspaceDialog organizationId={context.organizationId} open={creating} onOpenChange={setCreating}/></Suspense>}</div>
}
