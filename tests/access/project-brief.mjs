// Local-only full workflow integration. Run studio-leadership.mjs first.
import assert from 'node:assert/strict'
import { readFileSync,writeFileSync,chmodSync } from 'node:fs'
import { createRequire } from 'node:module'
const require=createRequire(new URL('../../app/package.json',import.meta.url))
const {createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url)))
const f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const url=new URL(config.API_URL)
assert(['localhost','127.0.0.1'].includes(url.hostname)&&url.port==='58321')
const options={auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input,init)=>fetch(input,{...init,signal:AbortSignal.timeout(20000)})}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,options),anon=createClient(config.API_URL,config.ANON_KEY,options)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data}
const denied=(r,code='42501')=>assert.equal(r.error?.code,code,r.error?.message??'Unexpected permission grant')
async function login(email){const c=createClient(config.API_URL,config.ANON_KEY,options);ok(await c.auth.signInWithPassword({email,password:f.password}));return c}
const lead=await login(f.people.senior.email),owner=await login(f.people.owner.email),junior=await login(f.people.junior.email),outsider=await login(f.people.reserve.email)
const stamp=Date.now(),clients={}
for(const [key,role] of [['client','approver'],['otherClient','approver'],['consultant','reviewer']]){
 const email=`brief-${key.toLowerCase()}-${stamp}@example.test`
 const user=ok(await service.auth.admin.createUser({email,password:f.password,email_confirm:true,user_metadata:{display_name:`Brief ${key}`}})).user
 const c=await login(email)
 const i=ok(await lead.rpc('invite_stakeholder',{p_workspace_id:f.wsA,p_project_id:f.pA1,p_email:email,p_role:role,p_display_name:`Brief ${key}`}))[0]
 ok(await c.rpc('claim_stakeholder_invitation',{p_token:i.out_token}))
 const p=ok(await service.from('project_participants').select('id').eq('project_id',f.pA1).eq('stakeholder_id',i.out_stakeholder_id).single())
 clients[key]={email,userId:user.id,participantId:p.id,stakeholderId:i.out_stakeholder_id,c}
}
const client=clients.client.c
const read=async(c=lead)=>ok(await c.rpc('get_project_brief',{p_project_id:f.pA1}))
let doc={disciplines:['interiors'],fields:[{id:'objective',label:'Project objective',help:'',answer:''},{id:'deliverables',label:'Expected deliverables',help:'',answer:''}],items:[],references:[]}
const save=async(c,d=doc)=>ok(await c.rpc('save_project_brief',{p_project_id:f.pA1,p_document:d,p_expected_version:(await read()).brief?.edit_version??0,p_respondent_participant_id:clients.client.participantId}))
const transition=async(action,c=lead)=>ok(await c.rpc('transition_project_brief',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_action:action}))
assert.equal((await read()).brief,null)
denied(await junior.rpc('save_project_brief',{p_project_id:f.pA1,p_document:doc,p_expected_version:0}))
await save(lead)
assert.equal((await read(client)).canEdit,true)
assert.equal((await read(clients.otherClient.c)).canEdit,false)
denied(await outsider.rpc('get_project_brief',{p_project_id:f.pA1}))
assert((await anon.rpc('get_project_brief',{p_project_id:f.pA1})).error)
denied(await lead.rpc('get_project_brief',{p_project_id:f.pB1}))
assert.equal(ok(await outsider.from('project_briefs').select('id')).length,0)
assert((await client.from('project_briefs').update({status:'agreed'}).eq('project_id',f.pA1)).error)
console.log('PASS leadership starts an incomplete brief; only the assigned client can edit it; reads and direct writes remain project-scoped')
const ownerMember=ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',f.people.owner.userId).single())
const ownerParticipant=ok(await service.from('project_participants').select('id').eq('project_id',f.pA1).eq('workspace_member_id',ownerMember.id).single())
ok(await lead.rpc('change_project_participant_role',{p_participant_id:ownerParticipant.id,p_role:'approver'}))
ok(await owner.rpc('save_project_brief',{p_project_id:f.pA1,p_document:doc,p_expected_version:(await read()).brief.edit_version,p_respondent_participant_id:ownerParticipant.id}))
const selfAgreement=await owner.rpc('transition_project_brief',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_action:'request_agreement'})
denied(selfAgreement,'23514')
assert.match(selfAgreement.error.message,/different project approver/)
ok(await lead.rpc('change_project_participant_role',{p_participant_id:ownerParticipant.id,p_role:'contributor'}))
await save(lead)
console.log('PASS a studio owner cannot request their own agreement even when holding both administrative and approver permissions')
const version=(await read()).brief.edit_version
const concurrent=await Promise.all([lead,client].map(c=>c.rpc('save_project_brief',{p_project_id:f.pA1,p_document:doc,p_expected_version:version,p_respondent_participant_id:clients.client.participantId})))
assert.equal(concurrent.filter(r=>!r.error).length,1)
assert.equal(concurrent.filter(r=>r.error?.code==='PT409').length,1)
const invalid=structuredClone(doc);invalid.fields[0].label={unsafe:'object'}
denied(await lead.rpc('save_project_brief',{p_project_id:f.pA1,p_document:invalid,p_expected_version:(await read()).brief.edit_version,p_respondent_participant_id:clients.client.participantId}),'22023')
const badLink=structuredClone(doc);badLink.references=[{id:'bad',label:'Unsafe link',url:'javascript:alert(1)'}]
denied(await lead.rpc('save_project_brief',{p_project_id:f.pA1,p_document:badLink,p_expected_version:(await read()).brief.edit_version,p_respondent_participant_id:clients.client.participantId}),'22023')
console.log('PASS concurrent saves detect conflicts and preserve the winning draft; malformed questions and unsafe reference URLs are rejected')
const path=`${f.pA1}/${crypto.randomUUID()}`
ok(await client.storage.from('brief-references').upload(path,new Blob(['Local reference file'],{type:'text/plain'})))
const fileVersion=(await read()).brief.edit_version
const fileRace=await Promise.all([
 client.rpc('register_project_brief_file',{p_project_id:f.pA1,p_expected_version:fileVersion,p_path:path,p_name:'Client reference.txt'}),
 lead.rpc('save_project_brief',{p_project_id:f.pA1,p_document:doc,p_expected_version:fileVersion,p_respondent_participant_id:clients.client.participantId}),
])
assert.equal(fileRace.filter(r=>!r.error).length,1)
assert.equal(fileRace.filter(r=>r.error?.code==='PT409').length,1)
const fileId=fileRace[0].error ? ok(await client.rpc('register_project_brief_file',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_path:path,p_name:'Client reference.txt'})) : fileRace[0].data
const signed=ok(await client.storage.from('brief-references').createSignedUrl(path,60))
assert.equal(await (await fetch(signed.signedUrl)).text(),'Local reference file')
assert((await outsider.storage.from('brief-references').createSignedUrl(path,60)).error)
assert((await junior.storage.from('brief-references').upload(`${f.pA1}/${crypto.randomUUID()}`,new Blob(['Unauthorized'],{type:'text/plain'}))).error)
assert((await client.storage.from('brief-references').update(path,new Blob(['Overwrite'],{type:'text/plain'}))).error)
await client.storage.from('brief-references').remove([path])
assert.equal(await (await fetch(signed.signedUrl)).text(),'Local reference file')
console.log('PASS reference upload, registration and download use private storage; outsiders cannot download and registered files cannot be overwritten or deleted')
denied(await client.rpc('transition_project_brief',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_action:'submit'}),'23514')
doc.fields[0].answer='Design a reception area for eight visitors.';doc.fields[1].answer='Layout, furniture specification and finish samples.'
doc.items=[{id:'seating',title:'Seat eight visitors',detail:'Accessible reception seating.',kind:'mandatory',priority:'high',source:'client',acceptance:'The agreed layout and furniture schedule show eight seats.',appliesTo:'Reception',ownerProfileId:'',resolution:''},{id:'finish',title:'Warm natural finish',detail:'Use the approved reference.',kind:'preference',priority:'medium',source:'client',acceptance:'Client compares the sample with the agreed reference.',appliesTo:'Furniture',ownerProfileId:'',resolution:''},{id:'measurements',title:'Existing measurements are current',detail:'Client-provided survey is the starting point.',kind:'assumption',priority:'medium',source:'client',acceptance:'',appliesTo:'',ownerProfileId:'',resolution:''},{id:'delivery',title:'Confirm delivery date',detail:'',kind:'question',priority:'high',source:'client',acceptance:'',appliesTo:'',ownerProfileId:'',resolution:''}]
doc.references=[{id:'reference',label:'Design reference',url:'https://example.com/reference'}]
await save(client)
ok(await junior.rpc('add_project_brief_note',{p_project_id:f.pA1,p_body:'Can the client confirm the delivery date?'}))
await transition('submit',client)
denied(await client.rpc('save_project_brief',{p_project_id:f.pA1,p_document:doc,p_expected_version:(await read()).brief.edit_version,p_respondent_participant_id:clients.client.participantId}))
denied(await client.rpc('transition_project_brief',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_action:'request_agreement'}))
denied(await lead.rpc('transition_project_brief',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_action:'request_agreement'}),'23514')
await transition('return_to_draft')
doc.items[3].resolution='Client confirmed delivery by the agreed project milestone.'
await save(lead)
const agreementVersion=(await read()).brief.edit_version
const requests=await Promise.all([lead,owner].map(c=>c.rpc('transition_project_brief',{p_project_id:f.pA1,p_expected_version:agreementVersion,p_action:'request_agreement'})))
assert.equal(requests.filter(r=>!r.error).length,1)
assert.equal(requests.filter(r=>r.error?.code==='PT409').length,1)
let state=await read(),r1=state.brief.current_revision_id
assert.equal(state.brief.status,'awaiting_agreement')
assert.equal(state.revisions[0].attachments[0].id,fileId)
assert.equal(state.revisions[0].document.items[0].ownerProfileId,f.people.senior.userId)
denied(await lead.rpc('save_project_brief',{p_project_id:f.pA1,p_document:doc,p_expected_version:state.brief.edit_version,p_respondent_participant_id:clients.client.participantId}),'23514')
denied(await clients.otherClient.c.rpc('respond_project_brief',{p_project_id:f.pA1,p_revision_id:r1,p_decision:'agreed'}))
denied(await client.rpc('respond_project_brief',{p_project_id:f.pA1,p_revision_id:r1,p_decision:'changes_requested'}),'22023')
ok(await client.rpc('respond_project_brief',{p_project_id:f.pA1,p_revision_id:r1,p_decision:'changes_requested',p_comment:'Please add a durable finish.'}))
doc.items[1].detail='Use a durable finish matching the approved reference.'
await save(lead)
await transition('request_agreement')
const r2=(await read()).brief.current_revision_id
denied(await client.rpc('respond_project_brief',{p_project_id:f.pA1,p_revision_id:r1,p_decision:'agreed'}),'PT409')
const decisions=await Promise.all([1,2].map(()=>client.rpc('respond_project_brief',{p_project_id:f.pA1,p_revision_id:r2,p_decision:'agreed',p_comment:'Agreed.'})))
assert.equal(decisions.filter(r=>!r.error).length,1)
assert.equal(decisions.filter(r=>r.error?.code==='PT409').length,1)
assert.equal((await read()).brief.status,'agreed')
console.log('PASS client submits, team clarifies questions, leadership reviews, and the named client agrees an exact immutable revision; stale/duplicate decisions are rejected')
denied(await client.rpc('generate_brief_requirements',{p_project_id:f.pA1,p_revision_id:r2}))
assert.equal(ok(await lead.rpc('generate_brief_requirements',{p_project_id:f.pA1,p_revision_id:r2})),2)
assert.equal(ok(await lead.rpc('generate_brief_requirements',{p_project_id:f.pA1,p_revision_id:r2})),0)
const links=ok(await service.from('project_brief_requirement_links').select('requirement_id').eq('revision_id',r2))
const requirements=ok(await service.from('requirements').select('title,description,status,owner_profile_id').in('id',links.map(l=>l.requirement_id)))
assert.equal(requirements.length,2)
assert(requirements.every(r=>r.status==='draft'&&r.owner_profile_id===f.people.senior.userId&&r.description.includes('Acceptance:')))
const filters={p_ws_id:f.wsA,p_proj_id:f.pA1,p_view:'all',p_status_filter:['draft'],p_limit:1}
const firstPage=ok(await lead.rpc('list_requirements_dashboard',filters))
assert.equal(firstPage.rows.length,1)
assert(firstPage.next_cursor)
const secondPage=ok(await lead.rpc('list_requirements_dashboard',{...filters,p_cursor_updated_at:firstPage.next_cursor.updated_at,p_cursor_id:firstPage.next_cursor.id}))
assert.equal(secondPage.rows.length,1)
assert.notEqual(secondPage.rows[0].requirement_id,firstPage.rows[0].requirement_id)
assert.equal(secondPage.next_cursor,null)
denied(await outsider.rpc('list_requirements_dashboard',filters))
assert.deepEqual(ok(await outsider.rpc('list_requirements_dashboard',{p_ws_id:f.wsA,p_proj_id:null,p_view:'all'})).rows,[])
console.log('PASS agreed mandatory requirements and preferences generate linked requirement drafts exactly once; assumptions/questions stay in the brief')
console.log('PASS generated draft requirements can be listed and paginated without duplicates; project and workspace permission filters remain enforced')
denied(await service.from('project_brief_revisions').update({document:{tampered:true}}).eq('id',r2),'23514')
denied(await service.from('project_brief_decisions').delete().eq('revision_id',r2),'23514')
const agreedDocument=structuredClone((await read()).revisions.find(r=>r.id===r2).document)
await transition('revise')
doc.fields[0].answer='A revised reception brief.';await save(lead)
ok(await lead.rpc('remove_project_brief_file',{p_project_id:f.pA1,p_expected_version:(await read()).brief.edit_version,p_file_id:fileId}))
state=await read()
assert.deepEqual(state.revisions.find(r=>r.id===r2).document,agreedDocument)
assert.equal(state.revisions.find(r=>r.id===r2).attachments.length,1)
assert.equal(state.files.length,0)
assert.equal(await (await fetch(ok(await client.storage.from('brief-references').createSignedUrl(path,60)).signedUrl)).text(),'Local reference file')
console.log('PASS later edits and removed references preserve previous agreements, decisions and downloadable reference files')
const fixture={...f,clients:Object.fromEntries(Object.entries(clients).map(([k,{c,...v}])=>[k,v])),agreedRevision:r2}
const fixturePath=new URL('../../ops/.tmp/brief-fixture.json',import.meta.url)
writeFileSync(fixturePath,JSON.stringify(fixture));chmodSync(fixturePath,0o600)
