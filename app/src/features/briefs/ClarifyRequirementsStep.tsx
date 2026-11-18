import { lazy, Suspense, useEffect, useRef, useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/ui/button'
import { useProjectAreas } from '@/features/areas/queries'
import type { ProjectBriefData } from './queries'
import { newBriefItem, type BriefDocument, type BriefItem, type BriefKind } from './model'

const AreaManager = lazy(() => import('@/features/areas/AreaManager'))
const AreaPicker = lazy(() => import('@/features/areas/AreaPicker'))
const panel = 'rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5'
const help = 'text-xs leading-relaxed text-[#6b625a]'
const kinds: Record<BriefKind, string> = { mandatory:'Requirement', preference:'Preference', assumption:'Assumption', question:'Question' }

function issues(item: BriefItem, owners: ProjectBriefData['owners']) {
  const notes: string[] = []
  if (!item.title.trim()) notes.push('Add a title before saving.')
  if (['mandatory','preference'].includes(item.kind)) {
    if (!item.acceptance?.trim()) notes.push('Describe how this will be checked before agreement.')
    if (item.ownerProfileId ? !owners.some(o => o.id === item.ownerProfileId) : !owners.length) notes.push('Choose an active responsible team member before agreement.')
  }
  if (item.kind === 'question' && !item.resolution?.trim()) notes.push('Resolve this question before agreement.')
  return notes
}
function LongField({id,label,value,onChange,disabled,maxLength=5000,hint}:{id:string;label:string;value:string;onChange:(value:string)=>void;disabled:boolean;maxLength?:number;hint?:string}) {
  return <div className="space-y-1.5"><label htmlFor={id} className="block text-sm font-medium">{label}</label>{hint&&<p id={id+'-help'} className={help}>{hint}</p>}<textarea id={id} aria-describedby={hint?id+'-help':undefined} className="auth-field min-h-20 w-full resize-y" rows={3} maxLength={maxLength} value={value??''} disabled={disabled} onChange={e=>onChange(e.target.value)}/></div>
}
function ItemCard({item,index,projectId,owners,canEdit,busy,open,onOpen,change,remove,scope,hasAreas}:{
  item:BriefItem; index:number; projectId:string; owners:ProjectBriefData['owners']; canEdit:boolean; busy:boolean; open:boolean
  onOpen:(open:boolean)=>void; change:(patch:Partial<BriefItem>)=>void; remove:()=>void; scope:string; hasAreas:boolean
}) {
  const notes=issues(item,owners), owner=owners.find(o=>o.id===item.ownerProfileId)?.name ?? (item.ownerProfileId?'Previously assigned team member':'Automatic project assignment')
  return <section id={`brief-item-${item.id}`} tabIndex={-1} className={panel} aria-label={`Brief item ${index+1}`}>
    <details open={!canEdit||open} onToggle={e=>{if(e.target===e.currentTarget)onOpen(e.currentTarget.open)}}>
      <summary className="cursor-pointer [overflow-wrap:anywhere]"><span className="ml-1 text-xs font-medium text-[#8a4a17]">{kinds[item.kind]}</span><span className="ml-2 font-semibold">{item.title.trim()||`Untitled ${kinds[item.kind].toLowerCase()}`}</span>
        <span className={'mt-2 block '+help}>{canEdit?scope+' · ':''}{owner}{canEdit&&notes.length?' · Needs clarification':''}</span>
      </summary>
      <div className="mt-5 space-y-4">
        {canEdit ? <>
          <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_160px]"><label className="text-sm font-medium">Item title<input className="auth-field mt-1 w-full" id={`item-title-${item.id}`} value={item.title} maxLength={200} disabled={busy} placeholder="Describe one clear need" onChange={e=>change({title:e.target.value})}/></label><label className="text-sm">Kind<select className="auth-field mt-1 w-full" aria-label="Kind" value={item.kind} disabled={busy} onChange={e=>change({kind:e.target.value as BriefKind})}>{Object.entries(kinds).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label></div>
          <LongField id={`item-detail-${item.id}`} label="Details" value={item.detail} disabled={busy} hint="Add the context needed to understand this item." onChange={detail=>change({detail})}/>
          {['mandatory','preference'].includes(item.kind)&&<LongField id={`item-acceptance-${item.id}`} label="How will we check this?" value={item.acceptance} maxLength={3000} disabled={busy} hint="Before agreement: describe a measurement, test, sample, reference or named person's judgement." onChange={acceptance=>change({acceptance})}/>}
          {item.kind==='question'&&<LongField id={`item-resolution-${item.id}`} label="Answer / resolution" value={item.resolution} maxLength={3000} disabled={busy} hint="Leave this open while gathering information; record the answer before agreement." onChange={resolution=>change({resolution})}/>}
          <label className="block text-sm">Responsible person<select className="auth-field mt-1 w-full" aria-label="Responsible person" id={`item-owner-${item.id}`} value={item.ownerProfileId} disabled={busy} onChange={e=>change({ownerProfileId:e.target.value})}><option value="">Automatic project assignment</option>{item.ownerProfileId&&!owners.some(o=>o.id===item.ownerProfileId)&&<option value={item.ownerProfileId}>Previously assigned member · choose a current person</option>}{owners.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></label>
          {hasAreas||Boolean(item.areaIds?.length) ? <Suspense fallback={<p role="status">Loading area selection…</p>}><AreaPicker projectId={projectId} value={item.areaIds??[]} onChange={areaIds=>change({areaIds})} disabled={busy}/></Suspense> : <p className={help}>Applies to the whole project. Add optional areas above if you need a more specific scope.</p>}
          <details className="rounded-lg border border-[#efe8df] p-3"><summary className="auth-link cursor-pointer text-sm">Additional item details</summary><div className="mt-3 grid gap-3 sm:grid-cols-2">
            <label className="text-sm sm:col-span-2">Applies to<input className="auth-field mt-1 w-full" value={item.appliesTo} maxLength={1000} disabled={busy} placeholder="Optional scope note, such as a component or activity" onChange={e=>change({appliesTo:e.target.value})}/></label>
            <label className="text-sm">Priority<select className="auth-field mt-1 w-full" aria-label="Priority" value={item.priority} disabled={busy} onChange={e=>change({priority:e.target.value as BriefItem['priority']})}>{['critical','high','medium','low','informational'].map(p=><option key={p} value={p}>{p}</option>)}</select></label>
            <label className="text-sm">Source<select className="auth-field mt-1 w-full" aria-label="Source" value={item.source} disabled={busy} onChange={e=>change({source:e.target.value as BriefItem['source']})}><option value="client">Client</option><option value="consultant">Consultant</option><option value="internal_team">Internal team</option><option value="other">Other</option></select></label>
          </div></details>
          {notes.length>0&&<ul className="space-y-1 rounded-lg bg-[#fff4e5] p-3 text-xs text-[#8a4a17]" aria-label="Items to clarify">{notes.map(note=><li key={note}>{note}</li>)}</ul>}
          <Button variant="ghost" size="sm" disabled={busy} onClick={remove}>Remove item</Button>
        </> : <>
          {item.detail&&<p className="whitespace-pre-wrap text-sm">{item.detail}</p>}
          <Suspense fallback={<p>Loading saved scope…</p>}><AreaPicker projectId={projectId} value={item.areaIds??[]} onChange={()=>{}} disabled snapshot={item.areaSnapshot}/></Suspense>
          {item.appliesTo&&<p className="text-sm">Scope note: {item.appliesTo}</p>}
          {['mandatory','preference'].includes(item.kind)&&<div><h3 className="text-sm font-medium">How this will be checked</h3><p className="mt-1 whitespace-pre-wrap text-sm">{item.acceptance||'Not recorded yet.'}</p></div>}
          {item.kind==='question'&&<div><h3 className="text-sm font-medium">Answer / resolution</h3><p className="mt-1 whitespace-pre-wrap text-sm">{item.resolution||'Not resolved yet.'}</p></div>}
          <p className={help}>Priority: {item.priority} · Source: {item.source.replaceAll('_',' ')}</p>
        </>}
      </div>
    </details>
  </section>
}

export default function ClarifyRequirementsStep({projectId,document,data,canEdit,busy,stale,dirty,history,areaDraftDirty,onAreaDraftChange,change,update,next,back,focus}:{
  focus?:{itemId:string;field:'title'|'acceptance'|'resolution'|'owner'|'detail';nonce:number}
  projectId:string; document:BriefDocument; data:ProjectBriefData; canEdit:boolean; busy:boolean; stale:boolean; dirty:boolean; history:boolean
  areaDraftDirty:boolean; onAreaDraftChange:(dirty:boolean)=>void; change:(id:string,patch:Partial<BriefItem>)=>void
  update:(fn:(doc:BriefDocument)=>BriefDocument)=>void; next:()=>void; back:()=>void
}) {
  const areas=useProjectAreas(projectId), undoToast=useRef<string|number|null>(null)
  useEffect(()=>()=>{if(undoToast.current!==null)toast.dismiss(undoToast.current)},[data.brief?.edit_version,canEdit,busy])
  const [search,setSearch]=useState(''),[filter,setFilter]=useState('all'),[newKind,setNewKind]=useState<BriefKind>('mandatory'),[expanded,setExpanded]=useState<Set<string>>(()=>new Set())
  useEffect(()=>{if(focus){setSearch('');setFilter('all');setExpanded(new Set([focus.itemId]))}},[focus?.itemId,focus?.field,focus?.nonce])
  useEffect(()=>{if(!focus||!expanded.has(focus.itemId)||search||filter!=='all')return;const frame=window.requestAnimationFrame(()=>{const el=canEdit?window.document.getElementById(`item-${focus.field}-${focus.itemId}`):window.document.getElementById(`brief-item-${focus.itemId}`);el?.focus();el?.scrollIntoView({block:'center',behavior:'smooth'})});return()=>window.cancelAnimationFrame(frame)},[focus?.itemId,focus?.field,focus?.nonce,expanded,search,filter,canEdit])
  const areaCount=areas.data?.areas.filter(a=>!a.archived).length
  const attention=document.items.filter(i=>issues(i,data.owners).length>0).length
  const unresolved=document.items.filter(i=>i.kind==='question'&&!i.resolution?.trim()).length
  const scope=(item:BriefItem)=>item.areaIds?.length ? (history?item.areaSnapshot?.map(a=>a.path).join(' · '):areas.data?.areas.filter(a=>item.areaIds?.includes(a.id)).map(a=>a.path).join(' · '))||'Assigned project areas' : 'Whole project'
  const matches=(item:BriefItem)=>(filter==='all'||filter===item.kind||filter==='attention'&&issues(item,data.owners).length>0)&&`${item.title} ${item.detail} ${item.appliesTo} ${scope(item)}`.toLowerCase().includes(search.trim().toLowerCase())
  const visible=document.items.filter(item=>matches(item)||canEdit&&expanded.has(item.id))
  const openItem=(id:string,open:boolean)=>setExpanded(current=>{if(current.has(id)===open)return current;const result=new Set(current);open?result.add(id):result.delete(id);return result})
  const add=()=>{const item={...newBriefItem(),kind:newKind};update(d=>({...d,items:[...d.items,item]}));setSearch('');setFilter('all');openItem(item.id,true);window.requestAnimationFrame(()=>window.document.getElementById(`item-title-${item.id}`)?.focus())}
  const remove=(item:BriefItem,index:number)=>{update(d=>({...d,items:d.items.filter(i=>i.id!==item.id)}));openItem(item.id,false);if(undoToast.current!==null)toast.dismiss(undoToast.current);undoToast.current=toast('Item removed',{action:{label:'Undo',onClick:()=>{update(d=>{if(d.items.some(i=>i.id===item.id))return d;const items=[...d.items];items.splice(Math.min(index,items.length),0,item);return {...d,items}});openItem(item.id,true)}}})}
  return <div className="space-y-5">
    <header className={panel+' space-y-3'}><h2 className="text-lg font-semibold">Requirements, preferences and unknowns</h2><p className="text-sm leading-relaxed text-[#6b625a]">Turn the overall needs into clear commitments. Separate requirements from preferences, assumptions and questions. Start project-wide; add areas only when they help.</p><p className={help}>{(['mandatory','preference','assumption','question'] as const).map(kind=>{const n=document.items.filter(i=>i.kind===kind).length;return `${n} ${kinds[kind].toLowerCase()}${n===1?'':'s'}${kind==='question'?` (${unresolved} unresolved)`:''}`}).join(' · ')}</p>{canEdit&&attention>0&&<button className="auth-link text-sm" onClick={()=>{setFilter('attention');setSearch('');setExpanded(new Set())}}>{attention} {attention===1?'item needs':'items need'} clarification before agreement</button>}</header>
    {!history&&<details className={panel}><summary className="auth-link cursor-pointer font-medium">Optional project areas{areaCount!==undefined?` · ${areaCount} ${areaCount===1?'area':'areas'}`:''}</summary><p className={'mt-3 '+help}>Use spaces, zones, products, components or your own labels. Save each area before moving to another step.</p><Suspense fallback={<p role="status">Loading project areas…</p>}><AreaManager projectId={projectId} embedded disabled={busy} onDraftChange={onAreaDraftChange}/></Suspense></details>}
    {history&&<p className={help}>Area names below are preserved from this brief revision.</p>}
    <div className="flex flex-wrap items-end gap-3">{canEdit&&<><label className="text-sm">New item type<select className="auth-field mt-1 block" aria-label="New item type" value={newKind} disabled={busy} onChange={e=>setNewKind(e.target.value as BriefKind)}>{Object.entries(kinds).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label><Button className="rounded-lg bg-[#d9622b] text-white" disabled={busy||document.items.length>=100} id="brief-add-item" onClick={add}>Add an item</Button></>}
      {document.items.length>0&&<><label className="w-full min-w-0 text-sm sm:w-auto sm:flex-1">Find an item<input className="auth-field mt-1 w-full" type="search" placeholder="Search title, details or area" value={search} onChange={e=>{setSearch(e.target.value);setExpanded(new Set())}}/></label><label className="w-full text-sm sm:w-auto">Show items<select className="auth-field mt-1 block w-full" aria-label="Show items" value={filter} onChange={e=>{setFilter(e.target.value);setExpanded(new Set())}}><option value="all">All items</option><option value="attention">Needs clarification</option>{Object.entries(kinds).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label></>}
    </div>
    {document.items.length===0&&<div className={panel}><h3 className="font-medium">Capture one need at a time</h3><p className={'mt-2 '+help}>Requirements are commitments; preferences describe choices; assumptions record what needs confirmation; open questions capture what you still need to learn.</p>{canEdit&&<p className={'mt-2 '+help}>Choose a type above and add your first item. You can save drafts while checks and answers are still being clarified.</p>}</div>}
    {document.items.length>=100&&canEdit&&<p className={help}>This brief has 100 items. Review or remove an item before adding another.</p>}
    {document.items.length>0&&<p className={help}>Showing {visible.length} of {document.items.length} items.{canEdit?' Open items stay visible while you edit them.':''}</p>}
    {document.items.length>0&&!visible.length&&<p className={panel}>No items match this view. <button className="auth-link" onClick={()=>{setSearch('');setFilter('all')}}>Clear filters</button></p>}
    {visible.map(item=><ItemCard key={item.id} item={item} index={document.items.findIndex(i=>i.id===item.id)} projectId={projectId} owners={data.owners} canEdit={canEdit} busy={busy} open={expanded.has(item.id)} onOpen={open=>openItem(item.id,open)} change={patch=>change(item.id,patch)} remove={()=>remove(item,document.items.findIndex(i=>i.id===item.id))} scope={scope(item)} hasAreas={areas.isLoading||areas.isError||Boolean(areas.data?.areas.some(a=>!a.archived))}/>)}
    <footer className={panel+' flex flex-wrap items-center justify-between gap-3'}><Button variant="ghost" disabled={busy} onClick={back}>Back to overall needs</Button><div className="space-y-2"><p className={help}>{areaDraftDirty?'Save or cancel your area changes before continuing.':dirty?'Save your draft to keep these changes.':'Continue when you are ready; agreement happens in the final step.'}</p><Button className="h-auto whitespace-normal rounded-lg bg-[#d9622b] px-4 py-2.5 text-white" disabled={busy||stale||areaDraftDirty} onClick={next}>{canEdit&&(dirty||!data.brief)?'Save and continue to references':'Continue to references'}</Button></div></footer>
  </div>
}
