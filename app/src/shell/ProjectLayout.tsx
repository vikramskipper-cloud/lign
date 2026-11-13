import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import { Link, Navigate, Outlet, useLocation, useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { useProject } from '@/shell/queries'
import { useProjectCapabilities } from '@/lib/capabilities'
import { AccessDeniedPage } from '@/shell/AccessDenied'

/**
 * Loads the project + capability map by URL params. Gates all inner routes on:
 *   1. project actually exists AND the URL's workspace matches its workspace
 *   2. caller has `project.view` (the entry-level capability)
 */
export function ProjectLayout() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()

  const qc=useQueryClient()
  const {user}=useSession()
  const location=useLocation()
  const project = useProject(proj_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')

  const section=location.pathname.split(`/project/${proj_id}/`)[1]?.split('/')[0]??''
  const designSection=['designs','asset','deliverables','deliverable','reviews','review','approvals','approval','releases','release'].includes(section)
  const ready=useQuery({
    queryKey:['project-setup',user?.id,proj_id],enabled:Boolean(user&&proj_id&&caps.data?.['project.view']),refetchInterval:15000,
    queryFn:async()=>{const {data,error}=await supabase.rpc('get_project_journey',{p_project_id:proj_id});if(error)throw error;return data as {briefReady:boolean;designReady:boolean}},
  })
  useEffect(()=>{if(ready.data?.designReady)void qc.invalidateQueries({queryKey:['project',proj_id,'capabilities']})},[ready.data?.designReady,proj_id,qc])
  if (project.isLoading || caps.isLoading) return <LoadingPage />
  if (project.isError || !project.data) return <Navigate to={`/workspace/${ws_id}/projects`} replace />

  // Workspace mismatch (e.g. someone hand-typed a wrong ws_id for a real project id)
  if (project.data.workspace_id !== ws_id) {
    return (
      <Navigate to={`/workspace/${project.data.workspace_id}/project/${proj_id}/overview`} replace />
    )
  }

  if (!caps.data?.['project.view']) {
    return <AccessDeniedPage capability="project.view" />
  }

  if(designSection){
    if(ready.isLoading)return <LoadingPage />
    if(ready.isError)return <div className="p-6"><p role="alert">Could not check brief agreement.</p><button className="auth-link mt-3" onClick={()=>void ready.refetch()}>Try again</button></div>
    if(!ready.data?.designReady)return <div className="mx-auto max-w-3xl space-y-3 p-6"><h1 className="text-xl font-semibold">{ready.data?.briefReady?'Accept the proposal before detailed design':'Agree the brief before design work'}</h1><p>{ready.data?.briefReady?'Prepare the design proposal, review it internally and have the assigned approver accept its exact revision.':'Gather requirements and references, then have the assigned approver agree the brief before preparing a design proposal.'}</p><p>Project people, requirements and reference boards remain available.</p><Link className="auth-link inline-block" to={`/workspace/${ws_id}/project/${proj_id}/${ready.data?.briefReady?'proposal':'brief'}`}>{ready.data?.briefReady?'Open design proposal':'Open project brief'}</Link></div>
  }
  return <Outlet />
}

ProjectLayout.handle = { navMode: 'project' as const }

export const Component = ProjectLayout
