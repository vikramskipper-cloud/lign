import * as React from 'react'
import {useMutation,useQueryClient} from '@tanstack/react-query'
import {toast} from 'sonner'
import {supabase} from '@/lib/supabase'
import {invalidateAccess} from '@/features/shared/invalidate'
import {humanizeError} from '@/features/shared/errors'
import {Button} from '@/ui/button'
import type {ProjectParticipantRow} from './queries'

export function ParticipantAccessEditor({person,workspaceId,projectId}:{person:ProjectParticipantRow;workspaceId:string;projectId:string}) {
 const qc=useQueryClient(),[label,setLabel]=React.useState(person.professionalLabel),[canSubmit,setCanSubmit]=React.useState(person.canSubmitDeliverables)
 React.useEffect(()=>{setLabel(person.professionalLabel);setCanSubmit(person.canSubmitDeliverables)},[person.professionalLabel,person.canSubmitDeliverables])
 const save=useMutation({mutationFn:async()=>{
  const {error}=await supabase.rpc('set_project_participant_access',{p_participant_id:person.id,p_professional_label:label,p_can_submit:person.role==='reviewer'&&canSubmit})
  if(error)throw error
 },onSuccess:()=>{invalidateAccess(qc,workspaceId,projectId);toast.success('Project access settings saved')},onError:e=>toast.error(humanizeError(e))})
 return <details className="mt-2"><summary className="auth-link cursor-pointer text-xs">Professional label and submission access</summary><div className="mt-3 space-y-3 rounded-lg border border-[--color-border] p-3"><label className="block text-sm" htmlFor={`professional-${person.id}`}>Professional label</label><input id={`professional-${person.id}`} className="auth-field" maxLength={80} value={label} disabled={save.isPending} placeholder="Structural consultant, client, fabric supplier…" onChange={e=>setLabel(e.target.value)} />{person.role==='reviewer'?<><label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={canSubmit} disabled={save.isPending} onChange={e=>setCanSubmit(e.target.checked)} />Can submit deliverables</label><p className="text-xs text-[--color-text-muted]">Their own draft submissions only. The project team reviews and publishes. This grants no publishing, approval or team-management access.</p></>:<p className="text-xs text-[--color-text-muted]">Additional submission access is available to reviewers. Project leads and contributors already have design upload permissions.</p>}<Button size="sm" variant="secondary" disabled={save.isPending} onClick={()=>save.mutate()}>{save.isPending?'Saving…':'Save access settings'}</Button></div></details>
}
