import * as React from 'react'
import { Link, useBlocker, useParams } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import { invalidateRequirementsLists } from '@/features/shared/invalidate'
import { FullPageLoader } from '@/ui/full-page-loader'
import { Button } from '@/ui/button'
import { Badge } from '@/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/ui/tabs'
import { relative } from '@/lib/formatDate'
import { useProjectBrief, type ProjectBriefData, type BriefFile } from './queries'
import { BRIEF_TEMPLATES, newBriefDocument, newBriefItem, type BriefDocument, type BriefItem, type BriefField } from './model'
import { BRIEF_STATUS_LABELS } from './status'

const panel = 'space-y-4 rounded-xl border border-[--color-border] bg-[--color-surface] p-5'
const help = 'text-xs leading-relaxed text-[--color-text-muted]'
const kinds = { mandatory:'Mandatory requirement',preference:'Preference',assumption:'Assumption',question:'Open question' }

function TextField({id,label,value,onChange,hint,disabled,rows=3}:{id:string;label:string;value:string;onChange:(value:string)=>void;hint?:string;disabled?:boolean;rows?:number}) {
  return <div className="space-y-1.5"><label htmlFor={id} className="block text-sm font-medium">{label}</label>{hint&&<p id={`${id}-help`} className={help}>{hint}</p>}<textarea id={id} aria-describedby={hint?`${id}-help`:undefined} className="auth-field min-h-20 resize-y" rows={rows} value={value} disabled={disabled} onChange={e=>onChange(e.target.value)} /></div>
}
function ReferenceDownload({file}:{file:BriefFile}) {
  const [pending,setPending]=React.useState(false)
  return <button type="button" className="auth-link break-all text-left text-sm" disabled={pending} onClick={async()=>{
    setPending(true)
    const {data,error}=await supabase.storage.from('brief-references').createSignedUrl(file.storage_path,60,{download:file.name})
    setPending(false)
    if(error) {toast.error(humanizeError(error));return}
    window.location.assign(data.signedUrl)
  }}>{pending?'Preparing download…':file.name} <span className={help}>({Math.ceil(file.size_bytes/1024)} KB)</span></button>
}

export function ProjectBriefScreen() {
  const {ws_id:workspaceId,proj_id:projectId}=useParams<{ws_id:string;proj_id:string}>()
  const query=useProjectBrief(projectId)
  if(query.isLoading) return <FullPageLoader label="Loading project brief" />
  if(!query.data||query.isError||!projectId||!workspaceId) return <div className="p-6"><h1 className="text-xl font-semibold">Brief unavailable</h1><p role="alert" className="mt-2 text-sm">You need access to this project to view its brief.</p><Button className="mt-3" variant="secondary" onClick={()=>void query.refetch()}>Try again</Button></div>
  if(!query.data.brief&&!query.data.canManage) return <div className="p-6"><h1 className="text-xl font-semibold">Project brief</h1><p className="mt-2 text-sm">Project leadership will start the brief and assign a client or project approver to complete it.</p></div>
  return <BriefEditor key={projectId} data={query.data} workspaceId={workspaceId} projectId={projectId} />
}

function BriefEditor({data,workspaceId,projectId}:{data:ProjectBriefData;workspaceId:string;projectId:string}) {
  const qc=useQueryClient()
  const [document,setDocument]=React.useState<BriefDocument>(()=>data.brief?.document??newBriefDocument())
  const [respondent,setRespondent]=React.useState(data.brief?.respondent_participant_id??'')
  const [loadedVersion,setLoadedVersion]=React.useState(data.brief?.edit_version??0)
  const [dirty,setDirty]=React.useState(false)
  const [tab,setTab]=React.useState(()=>new URLSearchParams(window.location.search).get('step')==='agreement'?'agreement':'brief')
  const [historyId,setHistoryId]=React.useState('')
  const [error,setError]=React.useState<string|null>(null)
  const [note,setNote]=React.useState('')
  const [decisionComment,setDecisionComment]=React.useState('')
  const [confirmedRevision,setConfirmedRevision]=React.useState('')
  const [uploading,setUploading]=React.useState(false)
  const currentVersion=data.brief?.edit_version??0
  const confirmationId=data.brief?.current_revision_id??''
  const confirmed=confirmedRevision!==''&&confirmedRevision===confirmationId
  React.useEffect(()=>{setConfirmedRevision('');setDecisionComment('')},[confirmationId])
  React.useEffect(()=>{
    if(!dirty) {setDocument(data.brief?.document??newBriefDocument());setRespondent(data.brief?.respondent_participant_id??'');setLoadedVersion(currentVersion)}
  },[currentVersion,dirty,data.brief])
  React.useEffect(()=>{
    if(!dirty)return
    const warn=(event:BeforeUnloadEvent)=>{event.preventDefault();event.returnValue=''}
    window.addEventListener('beforeunload',warn)
    return()=>window.removeEventListener('beforeunload',warn)
  },[dirty])
  const mutation=useMutation({
    mutationFn:async({rpc,args}:{rpc:string;args:Record<string,unknown>})=>{
      const result=await supabase.rpc(rpc,args)
      if(result.error)throw result.error
      return result.data
    },
    onSuccess:async()=>{
      invalidateRequirementsLists(qc,workspaceId,projectId)
      await Promise.all([qc.invalidateQueries({queryKey:['project-setup']}),qc.invalidateQueries({predicate:q=>q.queryKey[0]==='project'&&q.queryKey[1]===projectId&&q.queryKey[2]==='capabilities'}),qc.invalidateQueries({queryKey:['project-brief']}),qc.invalidateQueries({queryKey:['studio-overview']})])
    },
    onError:(err)=>setError(humanizeError(err)),
  })
  const blocker=useBlocker(dirty&&!mutation.isPending)
  React.useEffect(()=>{
    if(blocker.state==='blocked') {
      if(window.confirm('Discard unsaved brief changes?')) blocker.proceed()
      else blocker.reset()
    }
  },[blocker])
  const busy=mutation.isPending||uploading
  const history=data.revisions.find(r=>r.id===historyId)
  const shownDocument=history?.document??document
  const files=history?.attachments??data.files
  const canEditDocument=!history&&(data.canEdit||(!data.brief&&data.canManage))
  const editable=canEditDocument&&!busy
  const stale=dirty&&loadedVersion!==currentVersion
  const currentRevision=data.revisions.find(r=>r.id===data.brief?.current_revision_id)
  const shownRevision=history??currentRevision
  const mutateDocument=(fn:(doc:BriefDocument)=>BriefDocument)=>{setDocument(fn);setDirty(true);setError(null)}
  const changeField=(id:string,patch:Partial<BriefField>)=>mutateDocument(d=>({...d,fields:d.fields.map(f=>f.id===id?{...f,...patch}:f)}))
  const changeItem=(id:string,patch:Partial<BriefItem>)=>mutateDocument(d=>({...d,items:d.items.map(i=>i.id===id?{...i,...patch}:i)}))
  const run=async(rpc:string,args:Record<string,unknown>)=>{
    setError(null)
    try {const result=await mutation.mutateAsync({rpc,args});return {ok:true,result}}
    catch{return {ok:false,result:null}}
  }
  const save=async()=>{
    const result=await run('save_project_brief',{p_project_id:projectId,p_document:document,p_expected_version:loadedVersion,p_respondent_participant_id:respondent||null})
    if(result.ok){setDirty(false);toast.success('Brief saved')}
  }
  const transition=async(action:string)=>{
    const result=await run('transition_project_brief',{p_project_id:projectId,p_expected_version:loadedVersion,p_action:action})
    if(result.ok){setHistoryId('');setConfirmedRevision('');toast.success('Brief stage updated')}
  }
  const respond=async(decision:'agreed'|'changes_requested')=>{
    if(decision==='agreed'&&!confirmed)return
    const result=await run('respond_project_brief',{p_project_id:projectId,p_revision_id:decision==='agreed'?confirmedRevision:confirmationId,p_decision:decision,p_comment:decisionComment})
    if(result.ok){setDecisionComment('');setConfirmedRevision('');toast.success(decision==='agreed'?'Brief agreement recorded':'Changes requested')}
  }
  const upload=async(file:File)=>{
    if(file.size>10*1024*1024){setError('Choose a reference file of 10 MB or less.');return}
    setUploading(true);setError(null)
    const path=`${projectId}/${crypto.randomUUID()}`
    try {
      const result=await supabase.storage.from('brief-references').upload(path,file,{contentType:file.type||'application/octet-stream',upsert:false})
      if(result.error)throw result.error
      const registered=await run('register_project_brief_file',{p_project_id:projectId,p_expected_version:loadedVersion,p_path:path,p_name:file.name})
      if(!registered.ok)await supabase.storage.from('brief-references').remove([path])
    }catch(err){setError(humanizeError(err))}finally{setUploading(false)}
  }
  return <div className="lign-warm mx-auto w-full max-w-5xl space-y-5 p-5 md:p-7">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><h1 className="auth-display text-3xl">Project brief</h1><p className="mt-2 text-sm text-[--color-text-muted]">After project setup, gather requirements and references here, then review and agree the brief before design work.</p></div><div className="flex flex-wrap items-center gap-2"><Badge>{history?`Revision ${history.number}`:data.brief?BRIEF_STATUS_LABELS[data.brief.status]:'New brief'}</Badge>{dirty&&<Badge variant="warning">Unsaved changes</Badge>}{canEditDocument&&<Button onClick={()=>void save()} disabled={stale||busy}>{busy?'Working…':data.brief?'Save draft':'Save and start brief'}</Button>}</div></div>
    {error&&<p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    {stale&&<p role="alert" className="text-sm">Someone saved a newer version. Your edits are preserved here. <button type="button" className="auth-link" onClick={()=>{if(window.confirm('Discard your edits and load the latest brief?'))setDirty(false)}}>Reload latest brief</button></p>}
    {data.brief&&<div className="flex flex-wrap items-center gap-3"><label htmlFor="brief-history" className="text-sm">View</label><select id="brief-history" className="auth-field max-w-full sm:w-auto" value={historyId} disabled={dirty||busy} onChange={e=>{setHistoryId(e.target.value);setConfirmedRevision('')}}><option value="">Current working brief</option>{data.revisions.map(r=><option key={r.id} value={r.id}>Revision {r.number} · {r.decision?.decision==='agreed'?'Agreed':r.decision?.decision==='changes_requested'?'Changes requested':r.id===data.brief?.current_revision_id&&data.brief.status==='awaiting_agreement'?'Awaiting agreement':'Withdrawn'}</option>)}</select></div>}
    <Tabs value={tab} onValueChange={setTab}>
      <TabsList className="h-auto w-full flex-wrap justify-start gap-1"><TabsTrigger value="brief">1. Gather needs</TabsTrigger><TabsTrigger value="requirements">2. Clarify requirements</TabsTrigger><TabsTrigger value="references">3. References</TabsTrigger><TabsTrigger value="agreement">4. Review and agree</TabsTrigger></TabsList>
      <TabsContent value="brief" className="space-y-5">
        <section className={panel}><h2 className="font-semibold">Start with a template, or keep a blank brief</h2><p className={help}>Combine disciplines as needed. Templates add questions; existing answers stay in place when a template is deselected. Edit or remove optional questions below.</p><div className="flex flex-wrap gap-4">{BRIEF_TEMPLATES.map(t=><label key={t.id} className="flex items-center gap-2 text-sm"><input type="checkbox" disabled={!editable} checked={shownDocument.disciplines.includes(t.id)} onChange={e=>mutateDocument(d=>({...d,disciplines:e.target.checked?[...d.disciplines,t.id]:d.disciplines.filter(id=>id!==t.id),fields:e.target.checked?[...d.fields,...t.fields.filter(f=>!d.fields.some(existing=>existing.id===f.id)).map(f=>({...f}))]:d.fields}))} />{t.label}</label>)}</div></section>
        <section className={panel} aria-label="Brief questions">{shownDocument.fields.map(f=><div key={f.id} className="space-y-2 border-b border-[--color-border] pb-4 last:border-b-0"><TextField id={`brief-${f.id}`} label={f.label} hint={f.help} value={f.answer} disabled={!editable} onChange={answer=>changeField(f.id,{answer})} />{editable&&<details><summary className="auth-link cursor-pointer text-xs">Edit this question</summary><div className="mt-2 space-y-2"><label className="block text-xs">Question label<input className="auth-field mt-1" maxLength={200} value={f.label} onChange={e=>changeField(f.id,{label:e.target.value})} /></label><label className="block text-xs">Guidance<input className="auth-field mt-1" maxLength={500} value={f.help} onChange={e=>changeField(f.id,{help:e.target.value})} /></label>{!['objective','deliverables'].includes(f.id)&&<Button variant="ghost" size="sm" onClick={()=>mutateDocument(d=>({...d,fields:d.fields.filter(field=>field.id!==f.id)}))}>Remove question</Button>}</div></details>}</div>)}{editable&&<Button variant="secondary" onClick={()=>mutateDocument(d=>({...d,fields:[...d.fields,{id:crypto.randomUUID(),label:'Additional question',help:'',answer:''}]}))}>Add a question</Button>}</section>
      </TabsContent>
      <TabsContent value="requirements" className="space-y-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Requirements, preferences and unknowns</h2><p className={help}>Separate commitments from preferences, assumptions and open questions. Describe how requirements will be checked.</p></div>{editable&&<Button variant="secondary" onClick={()=>mutateDocument(d=>({...d,items:[...d.items,newBriefItem()]}))}>Add an item</Button>}</div>
        {shownDocument.items.length===0&&<p className={panel}>Add the needs that matter to this project. Resolve open questions before requesting agreement.</p>}
        {shownDocument.items.map((item,index)=><section key={item.id} className={panel} aria-label={`Brief item ${index+1}`}><div className="flex flex-wrap items-center justify-between gap-2"><Badge>{kinds[item.kind]}</Badge>{editable&&<Button variant="ghost" size="sm" onClick={()=>mutateDocument(d=>({...d,items:d.items.filter(i=>i.id!==item.id)}))}>Remove item</Button>}</div><div className="grid gap-3 sm:grid-cols-2"><label className="text-sm">Item title<input className="auth-field mt-1" value={item.title} maxLength={200} disabled={!editable} onChange={e=>changeItem(item.id,{title:e.target.value})} /></label><div className="text-sm"><label htmlFor={`item-kind-${item.id}`}>Kind</label><select id={`item-kind-${item.id}`} className="auth-field mt-1" value={item.kind} disabled={!editable} onChange={e=>changeItem(item.id,{kind:e.target.value as BriefItem['kind']})}>{Object.entries(kinds).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></div></div><TextField id={`item-detail-${item.id}`} label="Details" value={item.detail} disabled={!editable} onChange={detail=>changeItem(item.id,{detail})} /><div className="grid gap-3 sm:grid-cols-2"><label className="text-sm">Applies to<input className="auth-field mt-1" value={item.appliesTo} disabled={!editable} placeholder="Whole project, space, component, item, garment…" onChange={e=>changeItem(item.id,{appliesTo:e.target.value})} /></label><div className="text-sm"><label htmlFor={`item-owner-${item.id}`}>Responsible person</label><select id={`item-owner-${item.id}`} className="auth-field mt-1" value={item.ownerProfileId} disabled={!editable} onChange={e=>changeItem(item.id,{ownerProfileId:e.target.value})}><option value="">Project lead (default)</option>{data.owners.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></div><div className="text-sm"><label htmlFor={`item-priority-${item.id}`}>Priority</label><select id={`item-priority-${item.id}`} className="auth-field mt-1" value={item.priority} disabled={!editable} onChange={e=>changeItem(item.id,{priority:e.target.value as BriefItem['priority']})}>{['critical','high','medium','low','informational'].map(p=><option key={p} value={p}>{p}</option>)}</select></div><div className="text-sm"><label htmlFor={`item-source-${item.id}`}>Source</label><select id={`item-source-${item.id}`} className="auth-field mt-1" value={item.source} disabled={!editable} onChange={e=>changeItem(item.id,{source:e.target.value as BriefItem['source']})}><option value="client">Client</option><option value="consultant">Consultant</option><option value="internal_team">Internal team</option><option value="other">Other</option></select></div></div>{['mandatory','preference'].includes(item.kind)&&<TextField id={`item-acceptance-${item.id}`} label="How will we check this?" hint="A measurement with units, test, sample, reference or named person's judgement." value={item.acceptance} disabled={!editable} onChange={acceptance=>changeItem(item.id,{acceptance})} />}{item.kind==='question'&&<TextField id={`item-resolution-${item.id}`} label="Answer / resolution" hint="Record the answer before requesting agreement. Use a clarification note below to discuss it." value={item.resolution} disabled={!editable} onChange={resolution=>changeItem(item.id,{resolution})} />}</section>)}
      </TabsContent>
      <TabsContent value="references" className="space-y-4"><section className={panel}><h2 className="font-semibold">Reference links</h2><p className={help}>Add labelled links to inspiration, specifications, site information, size charts or other source material.</p>{shownDocument.references.map(ref=><div key={ref.id} className="space-y-2">{editable?<div className="grid gap-2 sm:grid-cols-2"><label className="text-sm">Reference label<input className="auth-field mt-1" value={ref.label} maxLength={200} onChange={e=>mutateDocument(d=>({...d,references:d.references.map(r=>r.id===ref.id?{...r,label:e.target.value}:r)}))} /></label><label className="text-sm">Reference URL<input className="auth-field mt-1" type="url" value={ref.url} onChange={e=>mutateDocument(d=>({...d,references:d.references.map(r=>r.id===ref.id?{...r,url:e.target.value}:r)}))} /></label><Button variant="ghost" size="sm" onClick={()=>mutateDocument(d=>({...d,references:d.references.filter(r=>r.id!==ref.id)}))}>Remove link</Button></div>:<a className="auth-link break-all text-sm" href={ref.url} target="_blank" rel="noopener noreferrer">{ref.label}</a>}</div>)}{editable&&<Button variant="secondary" onClick={()=>mutateDocument(d=>({...d,references:[...d.references,{id:crypto.randomUUID(),label:'',url:''}]}))}>Add a reference link</Button>}</section><section className={panel}><h2 className="font-semibold">Reference files</h2><p className={help}>Private to this project. PDF, PNG, JPEG, WebP, TXT, CSV, DOCX and XLSX; up to 10 MB per file. Saved agreement revisions retain their reference files.</p>{files.map(f=><div key={f.id} className="flex flex-wrap items-center justify-between gap-2"><ReferenceDownload file={f} />{editable&&<Button variant="ghost" size="sm" disabled={dirty} onClick={()=>void run('remove_project_brief_file',{p_project_id:projectId,p_expected_version:loadedVersion,p_file_id:f.id})}>Remove reference</Button>}</div>)}{editable&&<label className="block text-sm">Upload reference file<input className="mt-2 block max-w-full text-sm" type="file" disabled={dirty||!data.brief} accept=".pdf,.png,.jpg,.jpeg,.webp,.txt,.csv,.docx,.xlsx" onChange={e=>{const file=e.target.files?.[0];e.target.value='';if(file)void upload(file)}} /></label>}{editable&&(dirty||!data.brief)&&<p className={help}>Save your draft before uploading or removing files.</p>}{uploading&&<p role="status" className="text-sm">Uploading reference…</p>}</section></TabsContent>
      <TabsContent value="agreement" className="space-y-4"><section className={panel}><h2 className="font-semibold">Review and agreement</h2><p className={help}>The assigned approver can complete the draft and agree the exact revision reviewed by project leadership. Requirements agreement is separate from later design approvals.</p><div className="text-sm"><label htmlFor="brief-approver">Client / brief approver</label><select id="brief-approver" className="auth-field mt-1" value={history?history.respondent_participant_id:respondent} disabled={!editable||!data.canManage} onChange={e=>{setRespondent(e.target.value);setDirty(true)}}><option value="">Choose a project approver</option>{data.approvers.map(a=><option key={a.id} value={a.id}>{a.name}{a.pending?' (invitation pending)':''}</option>)}</select></div>{data.approvers.length===0&&<p className={help}>Add an approver through <Link className="auth-link" to={`/workspace/${workspaceId}/project/${projectId}/people`}>Project people</Link>, then assign them here.</p>}{dirty&&<p className={help}>Save your draft before submitting or requesting agreement.</p>}{!history&&data.brief&&<div className="flex flex-wrap gap-2">{data.brief.status==='draft'&&(data.canEdit||data.canManage)&&<Button variant="secondary" disabled={busy||dirty} onClick={()=>void transition('submit')}>Submit for team review</Button>}{data.canManage&&['draft','submitted'].includes(data.brief.status)&&<Button disabled={busy||dirty} onClick={()=>void transition('request_agreement')}>Review and request agreement</Button>}{data.canManage&&data.brief.status==='awaiting_agreement'&&<Button variant="secondary" disabled={busy} onClick={async()=>{try{await navigator.clipboard.writeText(`${window.location.origin}/workspace/${workspaceId}/project/${projectId}/brief?step=agreement`);toast.success('Agreement link copied')}catch{toast.error('Could not copy the link')}}}>Copy agreement link</Button>}{data.canManage&&['submitted','awaiting_agreement'].includes(data.brief.status)&&<Button variant="secondary" disabled={busy} onClick={()=>void transition('return_to_draft')}>Return to draft</Button>}{data.canManage&&data.brief.status==='agreed'&&<Button variant="secondary" disabled={busy} onClick={()=>void transition('revise')}>Start a new revision</Button>}</div>}
        {!history&&data.canRespond&&<div className="space-y-3 rounded-lg border border-[--color-border] p-4"><h3 className="font-medium">Your agreement on revision {currentRevision?.number}</h3><p className={help}>Review the questions, requirements and references in the other tabs before responding.</p><TextField id="brief-decision-comment" label="Agreement note or changes requested" value={decisionComment} onChange={setDecisionComment} disabled={busy} /><label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={confirmed} disabled={busy} onChange={e=>setConfirmedRevision(e.target.checked?confirmationId:'')} />I agree to this brief revision, including its requirements, preferences, assumptions and references.</label><div className="flex flex-wrap gap-2"><Button disabled={!confirmed||busy} onClick={()=>void respond('agreed')}>Agree this revision</Button><Button variant="secondary" disabled={!decisionComment.trim()||busy} onClick={()=>void respond('changes_requested')}>Request changes</Button></div></div>}
        {shownRevision&&<div className="space-y-2 text-sm"><p>Revision {shownRevision.number} · reviewed by project leadership {relative(shownRevision.created_at)}</p>{shownRevision.decision?<><p><strong>{shownRevision.decision.decision==='agreed'?'Agreed':'Changes requested'}</strong> by {shownRevision.decision.actorName} · {relative(shownRevision.decision.created_at)}</p>{shownRevision.decision.comment&&<p className="whitespace-pre-wrap">{shownRevision.decision.comment}</p>}</>:<p className={help}>{shownRevision.id===data.brief?.current_revision_id&&data.brief.status==='awaiting_agreement'?'Waiting for the assigned approver.':'This request is no longer current.'}</p>}{shownRevision.decision?.decision==='agreed'&&data.canGenerate&&data.canManage&&<><Button variant="secondary" disabled={busy} onClick={async()=>{const result=await run('generate_brief_requirements',{p_project_id:projectId,p_revision_id:shownRevision.id});if(result.ok)toast.success(`${result.result} new draft requirements created`)}}>Create draft requirements</Button><p className={help}>{shownRevision.generatedCount} drafts generated from this revision. Repeating this action does not duplicate them. New revisions create separate drafts for the team to review and supersede where needed.</p><Link className="auth-link" to={`/workspace/${workspaceId}/project/${projectId}/requirements?view=all&status=draft`}>Review and activate requirements</Link></>}</div>}
      </section></TabsContent>
    </Tabs>
    <section className={panel} aria-label="Brief clarification"><h2 className="font-semibold">Clarification notes</h2><p className={help}>Discuss unknowns here, then record the agreed answer in the brief before requesting agreement.</p>{data.notes.length===0&&<p className={help}>No clarification notes yet.</p>}{data.notes.map(n=><div key={n.id} className="border-t border-[--color-border] pt-3"><p className={help}>{n.authorName} · {relative(n.created_at)}</p><p className="mt-1 whitespace-pre-wrap break-words text-sm">{n.body}</p></div>)}{data.canComment&&<><TextField id="brief-note" label="Add a clarification note" value={note} onChange={setNote} disabled={busy} /><Button variant="secondary" disabled={!note.trim()||busy} onClick={async()=>{const result=await run('add_project_brief_note',{p_project_id:projectId,p_body:note});if(result.ok)setNote('')}}>Post note</Button></>}</section>
  </div>
}
