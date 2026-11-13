import {useParams,useSearchParams} from 'react-router'
import {useMyOrganizations} from './orgQueries'
import {useWorkspaces} from './queries'
import {useActiveWorkspaceId} from './useActiveWorkspace'
/** Presentation scope only. Existing workspace-scoped feeds remain unchanged. */
export function useNavigationContext(){
 const {org_id,ws_id}=useParams(),[params]=useSearchParams(),orgs=useMyOrganizations(),workspaces=useWorkspaces(),active=useActiveWorkspaceId(),all=workspaces.data??[],memberships=orgs.data??[]
 const current=all.find(w=>w.id===(ws_id??active.workspaceId)),known=(id:string|undefined|null)=>Boolean(id&&(memberships.some(o=>o.id===id)||all.some(w=>w.organization_id===id)))
 const requested=params.get('org'),organizationId=org_id??(ws_id?current?.organization_id:undefined)??(known(requested)?requested!:undefined)??current?.organization_id??memberships[0]?.id
 const organization=memberships.find(o=>o.id===organizationId),workspace=current?.organization_id===organizationId?current:all.find(w=>w.organization_id===organizationId)
 const options=[...memberships.map(o=>({id:o.id,name:o.name})),...Array.from(new Set(all.filter(w=>!memberships.some(o=>o.id===w.organization_id)).map(w=>w.organization_id))).map(id=>({id,name:'Shared · '+(all.find(w=>w.organization_id===id)?.name??'Projects')}))]
 return {organizationId,organizationName:organization?.name??options.find(o=>o.id===organizationId)?.name??'Your work',isAdmin:organization?.role==='owner'||organization?.role==='admin',workspaceId:ws_id??workspace?.id,workspaceName:workspace?.name,workspaces:all,organizations:options,isLoading:orgs.isLoading||workspaces.isLoading,isError:orgs.isError||workspaces.isError,refresh:()=>Promise.all([orgs.refetch(),workspaces.refetch()])}
}
