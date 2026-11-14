import {createContext} from 'react'
import {useQuery,useMutation,useQueryClient} from '@tanstack/react-query'
import {useSession} from '@/auth/SessionProvider'
import {supabase} from '@/lib/supabase'
export const DesignAudience=createContext<'internal'|'shared'>('internal')
export interface VersionAccess {internal:boolean;stage:'draft'|'submitted'|'changes_requested'|'approved';version:number;authorId:string|null;canReview:boolean;canPublish:boolean;canShare:boolean;note:string;recipients:{id:string;name:string;role:string;shared:boolean}[];history:{action:string;note:string;created_at:string;name:string}[]}
async function rpc<T>(name:string,args:Record<string,unknown>){const r=await supabase.rpc(name,args);if(r.error)throw r.error;return r.data as T}
export function useVersionAccess(id?:string){const {user}=useSession();return useQuery({queryKey:['version-access',user?.id,id],enabled:Boolean(id&&user),refetchInterval:15000,queryFn:()=>rpc<VersionAccess>('get_design_version_access',{p_version_id:id})})}
export function useVersionAccessAction(){const qc=useQueryClient();return useMutation({mutationFn:({name,args}:{name:string;args:Record<string,unknown>})=>rpc(name,args),onSuccess:async()=>{await Promise.all(['version-access','internal-review-queue'].map(key=>qc.invalidateQueries({queryKey:[key]})))}})}
