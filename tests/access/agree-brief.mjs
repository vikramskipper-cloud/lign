// Complete the real brief RPC flow when a design-focused local fixture needs it.
export async function ensureAgreedBrief(lead,approver,projectId,participantId){
 const ok=r=>{if(r.error)throw r.error;return r.data}
 if(ok(await lead.rpc('lign_project_ready_for_design',{p_project_id:projectId})))return
 const read=async()=>ok(await lead.rpc('get_project_brief',{p_project_id:projectId}))
 const document={disciplines:[],fields:[{id:'objective',label:'Objective',help:'',answer:'Verify the design workflow'},{id:'deliverables',label:'Deliverables',help:'',answer:'Design files and specifications'}],items:[{id:'sample-quality',kind:'mandatory',title:'Sample quality',detail:'Meet agreed quality',appliesTo:'Whole project',priority:'high',source:'client',ownerProfileId:'',acceptance:'Client reviews the sample',resolution:''}],references:[]}
 ok(await lead.rpc('save_project_brief',{p_project_id:projectId,p_document:document,p_expected_version:(await read()).brief?.edit_version??0,p_respondent_participant_id:participantId}))
 ok(await lead.rpc('transition_project_brief',{p_project_id:projectId,p_expected_version:(await read()).brief.edit_version,p_action:'request_agreement'}))
 ok(await approver.rpc('respond_project_brief',{p_project_id:projectId,p_revision_id:(await read()).brief.current_revision_id,p_decision:'agreed'}))
}
