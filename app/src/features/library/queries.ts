import {useContext,useRef,useState} from 'react'
import {useQuery,useQueryClient} from '@tanstack/react-query'
import {useSession} from '@/auth/SessionProvider'
import {supabase} from '@/lib/supabase'
import {humanizeError} from '@/features/shared/errors'
import {planningRpc,type PlanningFile} from '@/features/planning/queries'
import {LibraryActivity} from './LibraryActivity'
export interface Collection {id:string;title:string;kind:'template'|'references';description:string;edit_version:number;itemCount:number}
export interface LibraryItem {id:string;title:string;description:string;url:string|null;file_id:string|null;file:PlanningFile|null;edit_version:number}
export function useLibrary(org:string){const {user}=useSession();return useQuery({queryKey:['library',user?.id,org],enabled:Boolean(org&&user),queryFn:()=>planningRpc<{canManage:boolean;collections:Collection[]}>('get_organization_library',{p_organization_id:org})})}
export function useLibraryItems(id:string){const {user}=useSession();return useQuery({queryKey:['library-items',user?.id,id],enabled:Boolean(id&&user),queryFn:()=>planningRpc<LibraryItem[]>('get_library_items',{p_collection_id:id})})}
export function useLibraryAction(){const activity=useContext(LibraryActivity),qc=useQueryClient(),flight=useRef(false),[busy,setBusy]=useState(false),[error,setError]=useState('');return {busy,error,run:async<T,>(operation:()=>Promise<T>):Promise<{ok:true;data:T}|{ok:false}>=>{if(flight.current)return{ok:false};flight.current=true;activity(1);setBusy(true);setError('');try{const data=await operation();await Promise.all(['library','library-items','reference-boards','reference-board'].map(key=>qc.invalidateQueries({queryKey:[key]})));return{ok:true,data}}catch(e){setError(humanizeError(e));return{ok:false}}finally{flight.current=false;activity(-1);setBusy(false)}}}}
export async function uploadLibrary(org:string,file:File){const r=await planningRpc<{id:string;path:string}>('reserve_library_upload',{p_organization_id:org,p_name:file.name,p_mime:file.type||'application/octet-stream',p_size:file.size});try{const upload=await supabase.storage.from('organization-library').upload(r.path,file,{contentType:file.type,upsert:false});if(upload.error)throw upload.error;await planningRpc('finalize_library_upload',{p_file_id:r.id});return r.id}catch(e){await supabase.storage.from('organization-library').remove([r.path]);throw e}}
