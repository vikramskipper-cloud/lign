import { useEffect,useState } from 'react'
import { useMutation,useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import { invalidateRequirement,invalidateRequirementsLists } from '@/features/shared/invalidate'
import { Button } from '@/ui/button'
import { useRequirementAreas } from './queries'
import AreaPicker from './AreaPicker'
export default function RequirementAreaEditor({projectId,workspaceId,requirementId}:{projectId:string;workspaceId:string;requirementId:string}){
 const query=useRequirementAreas(requirementId),qc=useQueryClient(),[selected,setSelected]=useState<string[]>([]),[error,setError]=useState('')
 useEffect(()=>{if(query.data)setSelected(query.data.areas.map(a=>a.id))},[query.data])
 const mutation=useMutation({mutationFn:async()=>{const r=await supabase.rpc('set_requirement_areas',{p_requirement_id:requirementId,p_area_ids:selected});if(r.error)throw r.error},onSuccess:async()=>{setError('');invalidateRequirement(qc,requirementId);invalidateRequirementsLists(qc,workspaceId,projectId);await Promise.all([qc.invalidateQueries({queryKey:['requirement-areas']}),qc.invalidateQueries({queryKey:['area-requirements']})])},onError:e=>setError(humanizeError(e))})
 if(query.isLoading)return <p role="status">Loading requirement areas…</p>
 if(query.isError)return <p role="alert">Could not load requirement areas. <button className="auth-link" onClick={()=>void query.refetch()}>Retry</button></p>
 const d=query.data!,changed=[...selected].sort().join()!==d.areas.map(a=>a.id).sort().join()
 return <section className="space-y-3"><h3 className="font-medium">Project, spaces and zones</h3>{d.inherited&&<p className="text-sm">This sub-requirement inherits its parent requirement’s areas.</p>}<AreaPicker projectId={projectId} value={selected} onChange={setSelected} disabled={!d.canEdit||mutation.isPending} snapshot={d.areas}/>{d.canEdit&&<Button size="sm" disabled={!changed||mutation.isPending} onClick={()=>mutation.mutate()}>Save area assignment</Button>}{error&&<p role="alert" className="text-sm text-red-700">{error}</p>}</section>
}
