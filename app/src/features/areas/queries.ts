import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
export interface Area {id:string;parent_area_id:string|null;name:string;path:string;kind:string;depth:number;archived:boolean;description:string}
export interface AreaSnapshot {id:string;path:string;kind?:string;archived?:boolean}
export function useProjectAreas(projectId:string){
 const {user}=useSession()
 return useQuery({queryKey:['project-areas',user?.id,projectId],enabled:Boolean(user&&projectId),refetchInterval:30000,queryFn:async()=>{
 const {data,error}=await supabase.rpc('get_project_areas',{p_project_id:projectId});if(error)throw error;return data as {canManage:boolean;areas:Area[]}
 }})
}
export function useRequirementAreas(requirementId:string){
 const {user}=useSession()
 return useQuery({queryKey:['requirement-areas',user?.id,requirementId],enabled:Boolean(user&&requirementId),queryFn:async()=>{
 const {data,error}=await supabase.rpc('get_requirement_areas',{p_requirement_id:requirementId});if(error)throw error;return data as {canEdit:boolean;inherited:boolean;areas:AreaSnapshot[]}
 }})
}
