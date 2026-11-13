import {useState} from 'react'
import {useQuery} from '@tanstack/react-query'
import {useSession} from '@/auth/SessionProvider'
import {supabase} from '@/lib/supabase'
import {humanizeError} from '@/features/shared/errors'
import {type PlanningFile,help} from './queries'
export default function FilePreview({file,bucket=file.bucket??'project-planning'}:{file:PlanningFile;bucket?:string}){
 const {user}=useSession(),[error,setError]=useState(''),[busy,setBusy]=useState(false),isImage=['image/png','image/jpeg','image/webp'].includes(file.mime)
 const preview=useQuery({queryKey:['planning-image',user?.id,bucket,file.path],enabled:Boolean(user&&isImage),staleTime:45000,refetchInterval:50000,queryFn:async()=>{const r=await supabase.storage.from(bucket).createSignedUrl(file.path,60);if(r.error)throw r.error;return r.data.signedUrl}})
 return <div className="space-y-2">{isImage&&(preview.data?<img className="max-h-80 w-full rounded-lg object-contain" src={preview.data} alt={file.name} loading="lazy"/>:preview.isError?<p role="alert" className={help}>Preview unavailable. <button className="auth-link" onClick={()=>void preview.refetch()}>Retry</button></p>:<p className={help}>Loading image…</p>)}<button type="button" className="auth-link break-all text-left text-sm" disabled={busy} onClick={async()=>{setBusy(true);setError('');try{const r=await supabase.storage.from(bucket).createSignedUrl(file.path,60,{download:file.name});if(r.error)throw r.error;window.location.assign(r.data.signedUrl)}catch(e){setError(humanizeError(e))}finally{setBusy(false)}}}>{busy?'Preparing download…':file.name} <span className={help}>({Math.ceil(file.size/1024)} KB)</span></button>{error&&<p role="alert" className="text-sm text-red-700">{error}</p>}</div>
}
