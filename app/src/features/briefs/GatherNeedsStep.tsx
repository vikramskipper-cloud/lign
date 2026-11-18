import { Link } from 'react-router'
import { Button } from '@/ui/button'
import { useProject } from '@/shell/queries'
import { useProjectSummary } from '@/features/oversight/hub'
import type { BriefDocument, BriefField } from './model'
import type { ProjectBriefData } from './queries'

const panel = 'rounded-xl border border-[#e5ddd3] bg-[#fffdf9] p-5'
const help = 'text-xs leading-relaxed text-[--color-text-muted]'

function Question({ field, editable, change, remove }: {
  field: BriefField; editable: boolean
  change: (id: string, patch: Partial<BriefField>) => void; remove: (id: string) => void
}) {
  const required = ['objective', 'deliverables'].includes(field.id)
  return <div id={`brief-question-${field.id}`} tabIndex={-1} className="space-y-2 border-b border-[#efe8df] pb-5 last:border-b-0">
    <label htmlFor={`brief-${field.id}`} className="block text-sm font-medium">{field.label}</label>
    {field.help && <p id={`brief-${field.id}-help`} className={help}>{field.help}</p>}
    <textarea id={`brief-${field.id}`} aria-describedby={field.help ? `brief-${field.id}-help` : undefined} className="auth-field min-h-24 w-full resize-y" rows={3} value={field.answer} disabled={!editable} onChange={e => change(field.id, { answer:e.target.value })}/>
    {editable && <details><summary className="auth-link cursor-pointer text-xs">Edit this question</summary><div className="mt-3 space-y-2">
      <label className="block text-xs">Question label<input className="auth-field mt-1 w-full" maxLength={200} value={field.label} onChange={e => change(field.id,{label:e.target.value})}/></label>
      <label className="block text-xs">Guidance<input className="auth-field mt-1 w-full" maxLength={500} value={field.help} onChange={e => change(field.id,{help:e.target.value})}/></label>
      {!required && <Button variant="ghost" size="sm" onClick={() => remove(field.id)}>Remove question</Button>}
    </div></details>}
  </div>
}

export default function GatherNeedsStep({ projectId, workspaceId, document, data, respondent, editable, busy, stale, dirty, history, change, update, next, go, assign }: {
  projectId:string; workspaceId:string; document:BriefDocument; data:ProjectBriefData; respondent:string
  editable:boolean; busy:boolean; stale:boolean; dirty:boolean; history:boolean
  change:(id:string,patch:Partial<BriefField>)=>void; update:(fn:(doc:BriefDocument)=>BriefDocument)=>void
  next:()=>void; go:(tab:string)=>void; assign:(id:string)=>void
}) {
  const project = useProject(projectId), summary = useProjectSummary(projectId)
  const essentialIds = ['objective','deliverables','scope']
  const essentials = essentialIds.flatMap(id => document.fields.filter(f => f.id === id))
  const additional = document.fields.filter(f => !essentialIds.includes(f.id))
  const commitments = document.items.filter(i => i.kind === 'mandatory' || i.kind === 'preference')
  const unresolved = document.items.filter(i => i.kind === 'question' && !i.resolution.trim()).length
  const approver = data.approvers.find(a => a.id === respondent)
  const suggested = !respondent && data.approvers.length === 1 ? data.approvers[0] : undefined
  const checks = [
    { label:'Objective and deliverables captured', done:['objective','deliverables'].every(id => Boolean(document.fields.find(f=>f.id===id)?.answer.trim())), tab:'brief' },
    { label:'Requirements or preferences have clear checks', done:commitments.length>0 && commitments.every(i=>Boolean(i.title.trim() && i.acceptance.trim())), tab:'requirements' },
    { label:unresolved ? `${unresolved} open question${unresolved===1?'':'s'} to resolve` : 'No unresolved questions', done:unresolved===0, tab:'requirements' },
    { label:'Responsible team members identified', done:commitments.length>0 && commitments.every(i=>i.ownerProfileId ? data.owners.some(o=>o.id===i.ownerProfileId) : data.owners.length>0), tab:'requirements' },
    { label:approver ? `${approver.name}${approver.pending?' · invitation pending':' · brief approver'}` : 'Choose a brief approver', done:Boolean(approver && !approver.pending), tab:'agreement' },
  ]
  const preparing = !history && (data.canManage || data.canEdit) && (!data.brief || ['draft','submitted'].includes(data.brief.status))
  const remove = (id:string) => update(d=>({...d,fields:d.fields.filter(f=>f.id!==id)}))
  return <>
    <section className={panel} aria-label="Project context"><div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="font-semibold">{project.data?.name ?? 'Your project'}</h2><p className={'mt-2 '+help}>Client: {project.isError?'Could not load client details':project.data?.client_company || project.data?.client_contact_name || 'Not added yet'} · Project lead: {summary.isLoading?'Loading…':summary.isError?'Could not load lead':summary.data?.lead ?? 'Not assigned'}</p></div><Link className="auth-link text-sm" to={`/workspace/${workspaceId}/project/${projectId}/overview`}>Project details</Link></div></section>
    <div className={`grid items-start gap-5 ${preparing ? 'lg:grid-cols-[minmax(0,1fr)_280px]' : ''}`}>
      <div className="min-w-0 space-y-5">
        <section className={panel+' space-y-5'} aria-label="Brief essentials"><div><h2 className="text-lg font-semibold">Start with the essentials</h2><p className={'mt-2 '+help}>Capture the overall needs first. Describe the objective and deliverables before team review; add scope to make the boundaries clear. Save a draft at any point.</p></div>
          {essentials.map(field=><Question key={field.id} field={field} editable={editable} change={change} remove={remove}/>)}
          {!document.fields.some(f=>f.id==='scope') && editable && <Button variant="secondary" onClick={()=>update(d=>({...d,fields:[...d.fields,{id:'scope',label:'What is included and excluded?',help:'Define the boundaries of the work and any existing work to retain.',answer:''}]}))}>Add scope question</Button>}
        </section>
        <details className={panel} open={history || !data.canEdit && Boolean(data.brief) || undefined}><summary className="auth-link cursor-pointer font-medium">More project details ({additional.length} questions)</summary><p className={'mt-3 '+help}>Add budget, timing, audience and discipline-specific details when you have them. Unknowns can be clarified as the brief develops.</p><section className="mt-5 space-y-5" aria-label="Additional brief questions">{additional.map(field=><Question key={field.id} field={field} editable={editable} change={change} remove={remove}/>)}
          {editable && <Button variant="secondary" onClick={()=>update(d=>({...d,fields:[...d.fields,{id:crypto.randomUUID(),label:'Additional question',help:'',answer:''}]}))}>Add a question</Button>}
        </section></details>
        <div className={panel+' flex flex-wrap items-center justify-between gap-3'}><p className={help}>{history ? 'Viewing a saved revision.' : dirty ? 'Your changes need saving.' : data.brief ? 'Saved brief. Continue to the requirements when you are ready.' : 'Save your first draft to keep your progress.'}</p><Button className="h-auto whitespace-normal bg-[#d9622b] px-4 py-2.5 text-white hover:bg-[#c75221]" disabled={busy||stale} onClick={next}>{editable && (dirty||!data.brief) ? 'Save and continue to requirements' : 'Continue to requirements'}</Button></div>
      </div>
      {preparing && <aside className={panel+' space-y-4'} aria-label="Before brief agreement"><h2 className="font-semibold">Before client agreement</h2><p className={help}>You can work through these later. Project leadership reviews the brief before requesting agreement from a different approver.</p><ul className="space-y-3">{checks.map(check=><li key={check.tab+check.label} className="flex items-start gap-2 text-sm"><span aria-label={check.done?'Complete':'To do'}>{check.done?'✓':'○'}</span><button type="button" className="auth-link min-w-0 text-left [overflow-wrap:anywhere]" onClick={()=>go(check.tab)}>{check.label}</button></li>)}</ul><p className={help}>Spaces, zones and references are optional. Add them when they help explain the project.</p>
        {suggested && editable && data.canManage && <div className="space-y-2 border-t border-[#efe8df] pt-3"><p className={help}>An approver is already on this project. Assigning them here requires saving the draft.</p><Button variant="secondary" className="h-auto max-w-full whitespace-normal text-left [overflow-wrap:anywhere]" onClick={()=>assign(suggested.id)}>Use {suggested.name} as brief approver</Button></div>}
      </aside>}
    </div>
  </>
}
