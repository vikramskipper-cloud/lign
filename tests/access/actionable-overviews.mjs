// Local integration: truthful lifecycle summaries, actual action permissions and organisation scope.
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { createHash } from 'node:crypto'
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const cfg=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/planning-fixture.json',import.meta.url))),v=JSON.parse(readFileSync(new URL('../../ops/.tmp/version-sharing-fixture.json',import.meta.url)))
const url=new URL(cfg.API_URL);assert(['127.0.0.1','localhost'].includes(url.hostname)&&url.port==='58321','Local fixtures only')
const opts={auth:{persistSession:false,autoRefreshToken:false}},service=createClient(cfg.API_URL,cfg.SERVICE_ROLE_KEY,opts),anon=createClient(cfg.API_URL,cfg.ANON_KEY,opts)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data},deny=r=>assert(r.error,'Unexpected access')
async function login(p){const api=createClient(cfg.API_URL,cfg.ANON_KEY,opts);ok(await api.auth.signInWithPassword({email:p.email,password:f.password}));return api}
const owner=await login(f.people.owner),lead=await login(f.people.senior),junior=await login(f.people.junior),client=await login(v.people.client),viewer=await login(v.people.viewer),outsider=await login(f.people.outsider)
const member=async id=>ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',id).single()).id
const org=ok(await service.from('workspaces').select('organization_id').eq('id',f.wsA).single()).organization_id
const stamp=Date.now(),created=ok(await owner.rpc('create_project_full',{p_workspace_id:f.wsA,p_name:`Overview journey ${stamp}`,p_lead_member_id:await member(f.people.senior.userId),p_client_emails:[],p_code:`OV-${String(stamp).slice(-8)}`})),project=(Array.isArray(created)?created[0]:created).out_project_id
ok(await owner.rpc('add_project_participant',{p_project_id:project,p_workspace_member_id:await member(f.people.junior.userId),p_stakeholder_id:null,p_role:'contributor'}))
for(const [person,role]of [[v.people.client,'approver'],[v.people.viewer,'observer']])ok(await owner.rpc('add_project_participant',{p_project_id:project,p_workspace_member_id:null,p_stakeholder_id:person.sh,p_role:role}))
const participant=ok(await service.from('project_participants').select('id').eq('project_id',project).eq('stakeholder_id',v.people.client.sh).single()).id
const overview=async(api=owner)=>ok(await api.rpc('get_project_overview',{p_project_id:project})),brief=async()=>ok(await lead.rpc('get_project_brief',{p_project_id:project})),proposal=async()=>ok(await lead.rpc('get_project_proposal',{p_project_id:project}))
assert.equal((await overview()).phase,'Requirements & references');assert((await overview()).actions[0].canAct);assert.equal((await overview(viewer)).actions.length,0);deny(await outsider.rpc('get_project_overview',{p_project_id:project}));deny(await anon.rpc('get_project_overview',{p_project_id:project}))
const document={disciplines:[],fields:[{id:'objective',label:'Objective',help:'',answer:'A clear studio journey'},{id:'deliverables',label:'Deliverables',help:'',answer:'Design files and specifications'}],items:[{id:'quality',kind:'mandatory',title:'Durable finishes',detail:'Meet agreed quality',appliesTo:'Whole project',priority:'high',source:'client',ownerProfileId:'',acceptance:'Client reviews the sample',resolution:''}],references:[]}
ok(await lead.rpc('save_project_brief',{p_project_id:project,p_document:document,p_expected_version:0,p_respondent_participant_id:participant}))
ok(await lead.rpc('transition_project_brief',{p_project_id:project,p_expected_version:(await brief()).brief.edit_version,p_action:'request_agreement'}))
assert((await overview(client)).actions.find(a=>a.kind==='brief').canAct);assert.equal((await overview()).actions[0].canAct,false)
ok(await client.rpc('respond_project_brief',{p_project_id:project,p_revision_id:(await brief()).brief.current_revision_id,p_decision:'agreed'}))
assert.equal((await overview()).phase,'Design proposal');assert.equal((await overview(client)).actions.length,0)
const board=ok(await lead.rpc('save_reference_board',{p_project_id:project,p_title:'Overview direction',p_kind:'references'})),card=ok(await lead.rpc('save_reference_card',{p_board_id:board,p_title:'Design direction',p_url:'https://example.com/reference'}))
const proposalDoc={title:'Overview proposal',summary:'Respond to the brief',scope:'Agreed deliverables',budget:'To confirm',timing:'As agreed',assumptions:'No additional scope',sections:[{id:'concept',title:'Concept',concept:'Develop direction',materials:'As agreed',areaId:null}],referenceIds:[card],requirementIds:[]}
ok(await lead.rpc('save_project_proposal',{p_project_id:project,p_document:proposalDoc,p_brief_revision_id:(await brief()).brief.current_revision_id,p_respondent_id:participant,p_expected_version:0}))
ok(await lead.rpc('transition_project_proposal',{p_project_id:project,p_expected_version:(await proposal()).working.edit_version,p_action:'submit'}))
assert((await overview()).actions.find(a=>a.kind==='proposal').canAct);assert.equal((await overview(lead)).actions.find(a=>a.kind==='proposal').canAct,false);assert.equal((await overview(junior)).actions.find(a=>a.kind==='proposal').canAct,false)
ok(await owner.rpc('transition_project_proposal',{p_project_id:project,p_expected_version:(await proposal()).working.edit_version,p_action:'request_acceptance'}))
assert((await overview(client)).actions.find(a=>a.kind==='proposal').canAct);assert.equal((await overview(viewer)).actions.length,0)
ok(await client.rpc('respond_project_proposal',{p_project_id:project,p_revision_id:(await proposal()).currentRevisionId,p_decision:'accepted'}))
let summary=await overview();assert.equal(summary.phase,'Detailed design');assert.equal(summary.actions.length,0);assert(summary.accepted.briefRevision&&summary.accepted.proposalRevision);assert.equal((await overview(viewer)).accepted.proposalRevision,null)
const asset=ok(await lead.from('design_assets').insert({workspace_id:f.wsA,project_id:project,name:'Lobby elevations',created_by_profile_id:f.people.senior.userId}).select('id').single()).id
const version=ok(await lead.rpc('create_draft_version',{p_project_id:project,p_design_asset_id:asset})),body=`Overview sample ${stamp}`,reservation=ok(await lead.rpc('start_version_file_upload',{p_asset_version_id:version,p_checksum_hex:createHash('sha256').update(body).digest('hex'),p_mime_type:'text/plain',p_size_bytes:Buffer.byteLength(body)}))[0]
if(reservation.out_action==='upload_required')ok(await lead.storage.from(reservation.out_bucket).upload(reservation.out_object_path,new Blob([body],{type:'text/plain'})))
ok(await lead.rpc('finalize_version_file_upload',{p_file_id:reservation.out_file_id,p_asset_version_id:version,p_display_name:'Elevation.txt',p_role:'primary'}))
const access=async()=>ok(await lead.rpc('get_design_version_access',{p_version_id:version}))
ok(await lead.rpc('transition_design_version_review',{p_version_id:version,p_expected_version:(await access()).version,p_action:'submit'}))
assert((await overview()).actions.find(a=>a.kind==='internal_signoff').canAct);assert.equal((await overview(lead)).actions[0].canAct,false);assert.equal((await overview(client)).actions.length,0)
ok(await owner.rpc('transition_design_version_review',{p_version_id:version,p_expected_version:(await access()).version,p_action:'approve'}));assert.match((await overview()).actions[0].title,/Publish approved/)
ok(await lead.rpc('publish_version',{p_asset_version_id:version}));assert.equal((await overview()).actions.length,0);assert.equal((await overview(client)).shared.length,0)
const approval=ok(await lead.rpc('create_approval_draft',{p_project_id:project,p_design_asset_id:asset,p_version_id:version,p_policy:'single',p_approver_sh_ids:[v.people.client.sh],p_approver_wm_ids:[],p_title:'Client elevation decision'}))
assert.equal((await overview(client)).actions.length,0)
ok(await lead.rpc('send_approval_request',{p_approval_request_id:approval}))
summary=await overview(client);assert(summary.actions.find(a=>a.kind==='approval').canAct);assert.equal(summary.shared[0].id,version);assert.equal(summary.shared[0].recipients,null);assert.equal(summary.shared[0].decisionStatus,'pending');assert.equal((await overview(viewer)).shared.length,0)
// A published, unshared working package must not leak through an aggregate.
const next=ok(await lead.rpc('create_draft_version',{p_project_id:project,p_design_asset_id:asset,p_label:'PRIVATE FUTURE REVISION'}));assert(!JSON.stringify(await overview(client)).includes(next));assert(!JSON.stringify(await overview(viewer)).includes(version))
const second=ok(await owner.rpc('create_project_full',{p_workspace_id:f.wsB,p_name:`Cross-workspace overview ${stamp}`,p_client_emails:[]})),secondProject=(Array.isArray(second)?second[0]:second).out_project_id
let hub=ok(await owner.rpc('get_overview_hub',{p_organization_id:org,p_personal:true}));assert(hub.projects.some(p=>p.id===project));assert(hub.projects.some(p=>p.id===secondProject))
hub=ok(await owner.rpc('get_overview_hub',{p_organization_id:org,p_workspace_id:f.wsA}));assert(hub.projects.some(p=>p.id===project));assert(!hub.projects.some(p=>p.id===secondProject))
deny(await client.rpc('get_overview_hub',{p_organization_id:org}));hub=ok(await client.rpc('get_overview_hub',{p_organization_id:org,p_personal:true}));assert(!JSON.stringify(hub).includes(next));assert(!hub.projects.some(p=>p.id===secondProject))
deny(await owner.rpc('get_overview_hub',{p_organization_id:'00000000-0000-0000-0000-000000000001',p_workspace_id:f.wsA}));deny(await anon.rpc('list_organization_notifications',{p_organization_id:org}))
const inbox=ok(await client.rpc('list_organization_notifications',{p_organization_id:org,p_limit:1}));assert(inbox.rows.length);assert(inbox.rows.every(n=>n.recipient_profile_id===v.people.client.userId));assert(!JSON.stringify(inbox).includes(next))
if(inbox.has_more){const page=ok(await client.rpc('list_organization_notifications',{p_organization_id:org,p_before:inbox.next_cursor.created_at,p_before_id:inbox.next_cursor.id,p_limit:1}));assert(page.rows.every(n=>n.id!==inbox.rows[0].id))}
assert.equal(ok(await client.rpc('list_organization_notifications',{p_organization_id:org,p_workspace_id:f.wsB})).rows.length,0)
// Read mutation remains recipient-scoped and organisation-scoped.
const otherOrg=ok(await owner.rpc('list_organization_notifications',{p_organization_id:'00000000-0000-0000-0000-000000000001'}));assert.equal(otherOrg.rows.length,0)
ok(await owner.rpc('mark_organization_notifications_read',{p_organization_id:org,p_workspace_id:f.wsB}));assert((await client.rpc('list_organization_notifications',{p_organization_id:org})).data.facets.unread_count>0)
// Sequential approvers are actionable only when the previous slot is approved.
const nextApprover=await login(v.people.otherClient)
ok(await owner.rpc('add_project_participant',{p_project_id:project,p_workspace_member_id:null,p_stakeholder_id:v.people.otherClient.sh,p_role:'approver'}))
const sequenceAsset=ok(await lead.from('design_assets').insert({workspace_id:f.wsA,project_id:project,name:'Sequential elevations',created_by_profile_id:f.people.senior.userId}).select('id').single()).id
const sequenceVersion=ok(await lead.rpc('create_draft_version',{p_project_id:project,p_design_asset_id:sequenceAsset}))
const sequenceFile=ok(await lead.rpc('start_version_file_upload',{p_asset_version_id:sequenceVersion,p_checksum_hex:createHash('sha256').update(body).digest('hex'),p_mime_type:'text/plain',p_size_bytes:Buffer.byteLength(body)}))[0]
if(sequenceFile.out_action==='upload_required')ok(await lead.storage.from(sequenceFile.out_bucket).upload(sequenceFile.out_object_path,new Blob([body],{type:'text/plain'})))
ok(await lead.rpc('finalize_version_file_upload',{p_file_id:sequenceFile.out_file_id,p_asset_version_id:sequenceVersion,p_display_name:'Sequence.txt',p_role:'primary'}))
const seqAccess=async()=>ok(await lead.rpc('get_design_version_access',{p_version_id:sequenceVersion}))
ok(await lead.rpc('transition_design_version_review',{p_version_id:sequenceVersion,p_expected_version:(await seqAccess()).version,p_action:'submit'}))
ok(await owner.rpc('transition_design_version_review',{p_version_id:sequenceVersion,p_expected_version:(await seqAccess()).version,p_action:'approve'}))
ok(await lead.rpc('publish_version',{p_asset_version_id:sequenceVersion}))
const sequential=ok(await lead.rpc('create_approval_draft',{p_project_id:project,p_design_asset_id:sequenceAsset,p_version_id:sequenceVersion,p_policy:'sequential',p_approver_sh_ids:[v.people.client.sh,v.people.otherClient.sh],p_approver_wm_ids:[],p_approver_sort_order:[0,1],p_title:'Sequential decision'}))
ok(await lead.rpc('send_approval_request',{p_approval_request_id:sequential}))
assert.equal((await overview(nextApprover)).actions.find(a=>a.id==='approval-'+sequential).canAct,false)
const sequentialDetail=ok(await client.rpc('get_approval',{p_approval_request_id:sequential}))
ok(await client.rpc('respond_to_approval',{p_approver_slot_id:sequentialDetail.slots.find(x=>x.stakeholder_id===v.people.client.sh).id,p_decision:'approved',p_comment:'Accept this exact design'}))
assert.equal((await overview(nextApprover)).actions.find(a=>a.id==='approval-'+sequential).canAct,true)
// Consultant feedback opens the submission workflow, not a generic publish shortcut.
const consultant=await login(v.people.reviewer)
ok(await owner.rpc('add_project_participant',{p_project_id:project,p_workspace_member_id:null,p_stakeholder_id:v.people.reviewer.sh,p_role:'reviewer'}))
const consultantParticipant=ok(await service.from('project_participants').select('id').eq('project_id',project).eq('stakeholder_id',v.people.reviewer.sh).single()).id
ok(await owner.rpc('set_project_participant_access',{p_participant_id:consultantParticipant,p_professional_label:'Structural consultant',p_can_submit:true}))
const submission=ok(await consultant.rpc('create_deliverable_submission',{p_project_id:project,p_title:'Consultant package',p_asset_id:asset})),submissionVersion=ok(await service.from('deliverable_submissions').select('asset_version_id').eq('id',submission).single()).asset_version_id
const consultantBody='Consultant package '+stamp,consultantFile=ok(await consultant.rpc('start_version_file_upload',{p_asset_version_id:submissionVersion,p_checksum_hex:createHash('sha256').update(consultantBody).digest('hex'),p_mime_type:'text/plain',p_size_bytes:Buffer.byteLength(consultantBody)}))[0]
ok(await consultant.storage.from(consultantFile.out_bucket).upload(consultantFile.out_object_path,new Blob([consultantBody],{type:'text/plain'})))
ok(await consultant.rpc('finalize_version_file_upload',{p_file_id:consultantFile.out_file_id,p_asset_version_id:submissionVersion,p_display_name:'Consultant.txt',p_role:'primary'}))
ok(await consultant.rpc('transition_deliverable_submission',{p_submission_id:submission,p_action:'submit'}))
let consultantAction=(await overview()).actions.find(a=>a.id==='version-'+submissionVersion);assert(consultantAction.canAct);assert(consultantAction.to.endsWith('/deliverable/'+submission))
assert((await overview(consultant)).actions.some(a=>a.id==='submission-'+submission&&!a.canAct));assert(!(await overview(client)).actions.some(a=>a.id==='version-'+submissionVersion))
ok(await owner.rpc('transition_deliverable_submission',{p_submission_id:submission,p_action:'request_changes',p_note:'Clarify the structural detail'}))
assert((await overview(consultant)).actions.find(a=>a.id==='submission-'+submission).canAct)
assert.equal((await overview(lead)).actions.find(a=>a.id==='version-'+submissionVersion).canAct,false)
const archivedNotice=ok(await client.rpc('list_organization_notifications',{p_organization_id:org})).rows[0]
ok(await client.rpc('archive_notification',{p_notification_id:archivedNotice.id}));ok(await client.rpc('dismiss_notification',{p_notification_id:archivedNotice.id}))
assert(ok(await client.rpc('list_organization_notifications',{p_organization_id:org,p_tab:'archived'})).rows.some(n=>n.id===archivedNotice.id))
assert(ok(await client.rpc('list_organization_notifications',{p_organization_id:org,p_filters:{source:['approval']}})).rows.every(n=>n.event_type.startsWith('approval.')))
writeFileSync(new URL('../../ops/.tmp/overview-fixture.json',import.meta.url),JSON.stringify({project,secondProject,org,workspace:f.wsA,secondWorkspace:f.wsB,asset,version,next,approval,owner:f.people.owner,lead:f.people.senior,junior:f.people.junior,client:v.people.client,viewer:v.people.viewer,password:f.password}))
console.log('PASS lifecycle/independent sign-off permissions, exact accepted/shared revisions, private future versions, organisation/workspace aggregation, recipient-only inbox cursor and mark-read scope')
