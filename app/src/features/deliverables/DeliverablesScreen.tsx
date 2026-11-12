import * as React from 'react'
import {Link,useBlocker,useNavigate,useParams} from 'react-router'
import {useMutation,useQueryClient} from '@tanstack/react-query'
import {toast} from 'sonner'
import {supabase} from '@/lib/supabase'
import {useSession} from '@/auth/SessionProvider'
import {humanizeError} from '@/features/shared/errors'
import {invalidateAssetsForProject,invalidateVersionFiles} from '@/features/shared/invalidate'
import {useVersionFiles,type VersionFileRow} from '@/features/files/queries'
import {useUploadQueue} from '@/features/files/useUploadQueue'
import {formatBytes} from '@/features/files/mime'
import {FullPageLoader} from '@/ui/full-page-loader'
import {Button} from '@/ui/button'
import {Badge} from '@/ui/badge'
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from '@/ui/dialog'
import {relative} from '@/lib/formatDate'
import {useDeliverableSubmissions,type DeliverableData,type DeliverableSubmission, type SubmissionStage} from './queries'

const stages:Record<SubmissionStage,string>={draft:'Draft',submitted:'Awaiting team review',changes_requested:'Changes requested',accepted:'Accepted for publication',published:'Published',withdrawn:'Withdrawn'}
const panel='space-y-4 rounded-xl border border-[--color-border] bg-[--color-surface] p-5'
const help='text-xs leading-relaxed text-[--color-text-muted]'
function FileDownload({file}:{file:VersionFileRow}){
 const [busy,setBusy]=React.useState(false)
 return <button type="button" className="auth-link break-all text-left text-sm" disabled={busy} onClick={async()=>{
  setBusy(true);const {data,error}=await supabase.storage.from('lign-files').createSignedUrl(file.file.storage_ref,60,{download:file.display_name||'Deliverable'});setBusy(false)
  if(error){toast.error(humanizeError(error));return}window.location.assign(data.signedUrl)
 }}>{file.display_name||'Deliverable file'} <span className={help}>({formatBytes(file.file.size_bytes)})</span></button>
}
function SubmissionFiles({submission,editable,onBusy}:{submission:DeliverableSubmission;editable:boolean;onBusy:(busy:boolean)=>void}){
 const files=useVersionFiles(submission.asset_version_id),qc=useQueryClient()
 const queue=useUploadQueue({versionId:submission.asset_version_id,projectId:submission.project_id,assetId:submission.asset_id,hasPrimary:files.data?.some(f=>f.role==='primary')??false})
 const remove=useMutation({mutationFn:async(id:string)=>{const {error}=await supabase.rpc('remove_deliverable_file',{p_submission_id:submission.id,p_version_file_id:id});if(error)throw error},onSuccess:()=>invalidateVersionFiles(qc,submission.asset_version_id),onError:e=>toast.error(humanizeError(e))})
 const uploading=queue.items.some(i=>!['done','error'].includes(i.phase))
 React.useEffect(()=>{onBusy(uploading||remove.isPending)},[uploading,remove.isPending,onBusy])
 return <section className={panel} aria-label="Deliverable files"><h2 className="font-semibold">Files</h2><p className={help}>Drawings, specifications, calculations, samples or other design files. Up to 500 MB per file. Submitted files stay frozen during review.</p>{files.isLoading?<p className={help}>Loading files…</p>:files.isError?<p role="alert">Could not load files. <button className="auth-link" onClick={()=>void files.refetch()}>Try again</button></p>:files.data?.length===0?<p className={help}>No completed files yet.</p>:files.data?.map(f=><div key={f.id} className="flex flex-wrap items-center justify-between gap-2"><FileDownload file={f}/>{editable&&<Button size="sm" variant="ghost" disabled={uploading||remove.isPending} onClick={()=>remove.mutate(f.id)}>Remove {f.display_name||'file'}</Button>}</div>)}{editable&&<label className="block text-sm">Add deliverable files<input type="file" multiple className="mt-2 block max-w-full text-sm" disabled={remove.isPending||!files.isSuccess} onChange={e=>{if(e.target.files)queue.enqueue(Array.from(e.target.files));e.target.value=''}} /></label>}{queue.items.filter(i=>i.phase!=='done').map(i=><div key={i.id} className="space-y-1 text-sm"><p className="break-all">{i.name} · {i.phase==='error'?'Upload needs attention':`${i.phase} ${Math.round(i.progress*100)}%`}</p>{i.error&&<p role="alert" className="text-xs text-red-700">{i.error}</p>}{i.phase==='error'&&<div className="flex gap-2"><Button size="sm" variant="secondary" disabled={!editable} onClick={()=>queue.retry(i.id)}>Retry upload</Button><Button size="sm" variant="ghost" onClick={()=>queue.removeItem(i.id)}>Dismiss</Button></div>}</div>)}</section>
}

export function DeliverablesScreen(){
 const {ws_id:workspaceId,proj_id:projectId,submission_id:submissionId}=useParams<{ws_id:string;proj_id:string;submission_id?:string}>()
 const query=useDeliverableSubmissions(projectId)
 if(query.isLoading)return <FullPageLoader label="Loading deliverables"/>
 if(query.isError||!query.data||!workspaceId||!projectId)return <div className="p-6"><h1 className="text-xl font-semibold">Deliverables unavailable</h1><p role="alert" className="mt-2 text-sm">Project access is required to view submissions.</p><Button variant="secondary" className="mt-3" onClick={()=>void query.refetch()}>Try again</Button></div>
 return <SubmissionWorkspace key={submissionId??'list'} workspaceId={workspaceId} projectId={projectId} submissionId={submissionId} data={query.data}/>
}
function SubmissionWorkspace({workspaceId,projectId,submissionId,data}:{workspaceId:string;projectId:string;submissionId?:string;data:DeliverableData}){
 const {user}=useSession(),qc=useQueryClient(),navigate=useNavigate()
 const [createOpen,setCreateOpen]=React.useState(false),[title,setTitle]=React.useState(''),[notes,setNotes]=React.useState(''),[assetId,setAssetId]=React.useState('')
 const [filter,setFilter]=React.useState('all'),[note,setNote]=React.useState(''),[error,setError]=React.useState<string|null>(null),[uploading,setUploading]=React.useState(false)
 const inFlight=React.useRef(false)
 const submission=data.submissions.find(s=>s.id===submissionId)
 const mutation=useMutation({mutationFn:async({rpc,args}:{rpc:string;args:Record<string,unknown>})=>{const {data,error}=await supabase.rpc(rpc,args);if(error)throw error;return data},onSuccess:async()=>{
  invalidateAssetsForProject(qc,projectId)
  if(submission)invalidateVersionFiles(qc,submission.asset_version_id)
  await Promise.all([qc.invalidateQueries({queryKey:['deliverable-submissions']}),qc.invalidateQueries({queryKey:['deliverable-version']}),qc.invalidateQueries({queryKey:['studio-overview']})])
 },onError:e=>setError(humanizeError(e))})
 const blocker=useBlocker(uploading)
 React.useEffect(()=>{if(blocker.state==='blocked'){if(window.confirm('Leave while deliverable files are uploading?'))blocker.proceed();else blocker.reset()}},[blocker])
 React.useEffect(()=>{if(!uploading)return;const warn=(e:BeforeUnloadEvent)=>{e.preventDefault();e.returnValue=''};window.addEventListener('beforeunload',warn);return()=>window.removeEventListener('beforeunload',warn)},[uploading])
 const busy=mutation.isPending||uploading
 const run=async(rpc:string,args:Record<string,unknown>)=>{setError(null);try{return {ok:true,result:await mutation.mutateAsync({rpc,args})}}catch{return {ok:false,result:null}}}
 const create=async(parent?:DeliverableSubmission)=>{
  if(inFlight.current)return;inFlight.current=true
  const result=await run('create_deliverable_submission',{p_project_id:projectId,p_title:parent?.title??title,p_notes:parent?'':notes,p_asset_id:parent?.asset_id||assetId||null,p_parent_id:parent?.id??null})
  inFlight.current=false
  if(result.ok){setCreateOpen(false);setTitle('');setNotes('');setAssetId('');navigate(`/workspace/${workspaceId}/project/${projectId}/deliverable/${result.result}`)}
 }
 const action=async(action:string)=>{
  if(!submission)return
  const result=await run('transition_deliverable_submission',{p_submission_id:submission.id,p_action:action,p_note:note})
  if(result.ok){setNote('');toast.success('Submission updated')}
 }
 const own=submission?.author_id===user?.id
 const editable=Boolean(submission&&own&&data.canSubmit&&submission.stage==='draft'&&submission.versionStatus==='draft')
 return <div className="lign-warm mx-auto w-full max-w-5xl space-y-5 p-5 md:p-7"><div className="flex flex-wrap items-start justify-between gap-3"><div><h1 className="auth-display text-3xl">Deliverables</h1><p className="mt-2 text-sm text-[--color-text-muted]">Reviewer submissions, team review and publication.</p></div>{data.canSubmit&&!submissionId&&<Button onClick={()=>setCreateOpen(true)}>New deliverable draft</Button>}{submissionId&&<Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/deliverables`}>All submissions</Link>}</div>
  {error&&<p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
  {!submissionId?<><p className={help}>Reviewers need “Can submit deliverables” in Project people to upload their own drafts. A different project lead or contributor reviews each submission before publication.</p><label className="block text-sm" htmlFor="deliverable-filter">Submission status</label><select id="deliverable-filter" className="auth-field max-w-full sm:w-auto" value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">All submissions</option>{Object.entries(stages).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select>{data.submissions.filter(s=>filter==='all'||s.stage===filter).length===0&&<p className={panel}>No submissions match this view.</p>}{data.submissions.filter(s=>filter==='all'||s.stage===filter).map(s=><article key={s.id} className={panel}><div className="flex flex-wrap items-center justify-between gap-2"><Link className="auth-link font-medium" to={`/workspace/${workspaceId}/project/${projectId}/deliverable/${s.id}`}>{s.title}</Link><Badge>{stages[s.stage]}</Badge></div><p className={help}>{s.authorName}{s.professional_label?` · Professional: ${s.professional_label}`:''} · v{s.versionSequence} · {relative(s.created_at)}</p>{s.notes&&<p className="whitespace-pre-wrap break-words text-sm">{s.notes}</p>}</article>)}</>:!submission?<p role="alert" className={panel}>Submission not found in this project.</p>:<>
   <section className={panel}><div className="flex flex-wrap items-center justify-between gap-2"><h2 className="break-words text-xl font-semibold">{submission.title}</h2><Badge>{stages[submission.stage]}</Badge></div><p className={help}>Submitted by {submission.authorName}{submission.professional_label?` · Professional: ${submission.professional_label}`:''} · version {submission.versionSequence}</p>{submission.notes&&<p className="whitespace-pre-wrap break-words text-sm">{submission.notes}</p>}<Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/asset/${submission.asset_id}/v/${submission.asset_version_id}`}>Open version for review</Link>{submission.parent_submission_id&&<p><Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/deliverable/${submission.parent_submission_id}`}>Previous submission</Link></p>}</section>
   <SubmissionFiles key={submission.asset_version_id} submission={submission} editable={editable&&!mutation.isPending} onBusy={setUploading}/>
   <section className={panel}><h2 className="font-semibold">Review and publication</h2>{(editable||data.canReview&&submission.stage==='submitted'&&!own)&&<label className="block space-y-2 text-sm" htmlFor="deliverable-note">{editable?'Submission note (optional)':'Review note'}<textarea id="deliverable-note" className="auth-field min-h-24" maxLength={5000} value={note} disabled={busy} onChange={e=>setNote(e.target.value)}/></label>}<div className="flex flex-wrap gap-2">{editable&&<Button disabled={busy} onClick={()=>void action('submit')}>Submit for team review</Button>}{own&&data.canSubmit&&['draft','submitted'].includes(submission.stage)&&<Button variant="secondary" disabled={busy} onClick={()=>void action('withdraw')}>Withdraw submission</Button>}{data.canReview&&submission.stage==='submitted'&&!own&&<><Button disabled={busy} onClick={()=>void action('accept')}>Accept for publication</Button><Button variant="secondary" disabled={busy||!note.trim()} onClick={()=>void action('request_changes')}>Request changes</Button></>}{data.canReview&&submission.stage==='accepted'&&<Button disabled={busy} onClick={async()=>{const result=await run('publish_version',{p_asset_version_id:submission.asset_version_id});if(result.ok)toast.success('Accepted version published')}}>Publish accepted version</Button>}{data.canReview&&submission.stage==='published'&&!submission.isCurrent&&<Button variant="secondary" disabled={busy} onClick={async()=>{const result=await run('set_current_version',{p_design_asset_id:submission.asset_id,p_version_id:submission.asset_version_id});if(result.ok)toast.success('Current design version updated')}}>Set as current design</Button>}{own&&data.canSubmit&&submission.stage==='changes_requested'&&!submission.childId&&<Button disabled={busy} onClick={()=>void create(submission)}>Create revised draft</Button>}</div>{submission.childId&&<Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/deliverable/${submission.childId}`}>Open revised submission</Link>}{submission.stage==='draft'&&<p className={help}>Upload completed files before submitting. Your project role continues to govern comments and all other actions.</p>}{submission.stage==='submitted'&&<p className={help}>Files are frozen while the team reviews. Authors cannot accept their own submissions.</p>}{submission.stage==='changes_requested'&&<p className={help}>Create a revised draft and upload the revised files. This earlier submission remains unchanged.</p>}{submission.stage==='accepted'&&<p className={help}>Accepted files are frozen. A project lead or contributor can now publish this version.</p>}{submission.stage==='published'&&<p className={help}>{submission.isCurrent?'This is the current design version.':'Publication preserves the existing current design. Choose “Set as current design” when this version should replace it.'}</p>}</section>
   <section className={panel}><h2 className="font-semibold">Submission history</h2>{submission.events.map(e=><div key={e.id} className="border-t border-[--color-border] pt-3"><p className={help}>{e.actorName} · {e.action.replaceAll('_',' ')} · {relative(e.created_at)}</p>{e.note&&<p className="mt-1 whitespace-pre-wrap break-words text-sm">{e.note}</p>}</div>)}</section>
  </>}
  <Dialog open={createOpen} onOpenChange={open=>{if(!busy)setCreateOpen(open)}}><DialogContent className="lign-warm max-h-[90dvh] overflow-y-auto"><DialogHeader><DialogTitle>New deliverable draft</DialogTitle><DialogDescription>Upload your work for team review. The team controls publication and the current design version.</DialogDescription></DialogHeader><form className="space-y-4" onSubmit={e=>{e.preventDefault();if(title.trim())void create()}}>{error&&<p role="alert" className="text-sm text-red-700">{error}</p>}<label className="block space-y-1 text-sm" htmlFor="submission-title">Deliverable title<input id="submission-title" className="auth-field" maxLength={200} required value={title} disabled={busy} onChange={e=>setTitle(e.target.value)}/></label><div className="space-y-1 text-sm"><label htmlFor="submission-asset">Existing design asset (optional)</label><select id="submission-asset" className="auth-field" value={assetId} disabled={busy} onChange={e=>setAssetId(e.target.value)}><option value="">Create a new design asset</option>{data.assets.map(a=><option key={a.id} value={a.id}>{a.name}</option>)}</select></div><label className="block space-y-1 text-sm" htmlFor="submission-notes">Details<textarea id="submission-notes" className="auth-field min-h-24" maxLength={5000} value={notes} disabled={busy} onChange={e=>setNotes(e.target.value)}/></label><Button type="submit" disabled={!title.trim()||busy}>{busy?'Creating…':'Create draft'}</Button></form></DialogContent></Dialog>
 </div>
}
