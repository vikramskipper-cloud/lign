import {useQuery} from '@tanstack/react-query'
import {supabase} from '@/lib/supabase'
import {useSession} from '@/auth/SessionProvider'
export type SubmissionStage='draft'|'submitted'|'changes_requested'|'accepted'|'published'|'withdrawn'
export interface DeliverableSubmission {
 id:string;project_id:string;asset_id:string;asset_version_id:string;author_id:string;authorName:string;professional_label:string
 title:string;notes:string;stage:SubmissionStage;created_at:string;parent_submission_id:string|null;childId:string|null
 versionSequence:number;versionStatus:string;isCurrent:boolean
 events:{id:string;action:string;note:string;actorName:string;created_at:string}[]
}
export interface DeliverableData {canSubmit:boolean;canReview:boolean;assets:{id:string;name:string}[];submissions:DeliverableSubmission[]}
export function useDeliverableSubmissions(projectId?:string){
 const {user}=useSession()
 return useQuery({queryKey:['deliverable-submissions',user?.id,projectId],enabled:Boolean(user&&projectId),refetchInterval:30_000,
  retry:(count,error)=>(error as {code?:string}).code!=='42501'&&count<2,
  queryFn:async():Promise<DeliverableData>=>{const {data,error}=await supabase.rpc('get_deliverable_submissions',{p_project_id:projectId});if(error)throw error;return data as DeliverableData},
 })
}
export function useVersionSubmission(versionId?:string){
 const {user}=useSession()
 return useQuery({queryKey:['deliverable-version',user?.id,versionId],enabled:Boolean(user&&versionId),refetchInterval:30_000,
  queryFn:async()=>{const {data,error}=await supabase.from('deliverable_submissions').select('id,stage').eq('asset_version_id',versionId as string).maybeSingle();if(error)throw error;return data as {id:string;stage:SubmissionStage}|null},
 })
}
