// Complete the real brief RPC flow when a design-focused local fixture needs it.
export async function ensureAgreedBrief(lead,approver,projectId,participantId){
 const ok=r=>{if(r.error)throw r.error;return r.data}
 if(ok(await lead.rpc('lign_project_has_agreed_brief',{p_project_id:projectId})))return
 const read=async()=>ok(await lead.rpc('get_project_brief',{p_project_id:projectId}))
 const document={disciplines:[],fields:[{id:'objective',label:'Objective',help:'',answer:'Verify the design workflow'},{id:'deliverables',label:'Deliverables',help:'',answer:'Design files and specifications'}],items:[{id:'sample-quality',kind:'mandatory',title:'Sample quality',detail:'Meet agreed quality',appliesTo:'Whole project',priority:'high',source:'client',ownerProfileId:'',acceptance:'Client reviews the sample',resolution:''}],references:[]}
 ok(await lead.rpc('save_project_brief',{p_project_id:projectId,p_document:document,p_expected_version:(await read()).brief?.edit_version??0,p_respondent_participant_id:participantId}))
 ok(await lead.rpc('transition_project_brief',{p_project_id:projectId,p_expected_version:(await read()).brief.edit_version,p_action:'request_agreement'}))
 ok(await approver.rpc('respond_project_brief',{p_project_id:projectId,p_revision_id:(await read()).brief.current_revision_id,p_decision:'agreed'}))
}

// Design-focused fixtures pass both milestones through the real checked RPCs.
export async function ensureAcceptedProposal(lead,approver,projectId,participantId,internalReviewer=lead){
 const ok=r=>{if(r.error)throw r.error;return r.data}
 if(ok(await lead.rpc('lign_project_ready_for_design',{p_project_id:projectId})))return
 await ensureAgreedBrief(lead,approver,projectId,participantId)
 const brief=ok(await lead.rpc('get_project_brief',{p_project_id:projectId})),revision=brief.revisions.find(r=>r.decision?.decision==='agreed').id
 const board=ok(await lead.rpc('save_reference_board',{p_project_id:projectId,p_title:'Design workflow reference',p_kind:'references'}))
 const card=ok(await lead.rpc('save_reference_card',{p_board_id:board,p_title:'Agreed workflow direction',p_url:'https://example.com/design-direction'}))
 const document={title:'Design workflow proposal',summary:'Proceed under the agreed brief',scope:'The agreed design deliverables',budget:'To be confirmed',timing:'As agreed',assumptions:'No additional scope',sections:[{id:'concept',title:'Concept direction',concept:'Develop the agreed direction',materials:'As agreed',areaId:null}],referenceIds:[card],requirementIds:[]}
 let state=ok(await lead.rpc('get_project_proposal',{p_project_id:projectId}))
 ok(await lead.rpc('save_project_proposal',{p_project_id:projectId,p_document:document,p_brief_revision_id:revision,p_respondent_id:participantId,p_expected_version:state.working?.edit_version??0}))
 for(const action of ['submit','request_acceptance']){state=ok(await lead.rpc('get_project_proposal',{p_project_id:projectId}));ok(await (action==='request_acceptance'?internalReviewer:lead).rpc('transition_project_proposal',{p_project_id:projectId,p_expected_version:state.working.edit_version,p_action:action}))}
 state=ok(await approver.rpc('get_project_proposal',{p_project_id:projectId}))
 ok(await approver.rpc('respond_project_proposal',{p_project_id:projectId,p_revision_id:state.currentRevisionId,p_decision:'accepted'}))
}
