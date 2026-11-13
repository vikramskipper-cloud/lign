// Isolated backend checks. Run studio-leadership.mjs first. No hosted writes.
import assert from 'node:assert/strict'
import {ensureAcceptedProposal} from './agree-brief.mjs'
import {readFileSync,writeFileSync,chmodSync} from 'node:fs'
import {createRequire} from 'node:module'
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const url=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(url.hostname)&&url.port==='58321')
const opts={auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(i,o)=>fetch(i,{...o,signal:AbortSignal.timeout(20000)})}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,opts),anon=createClient(config.API_URL,config.ANON_KEY,opts)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data},denied=(r,c)=>assert.equal(r.error?.code,c,r.error?.message??'Unexpected success')
async function login(p){const c=createClient(config.API_URL,config.ANON_KEY,opts);ok(await c.auth.signInWithPassword({email:p.email,password:f.password}));return c}
const owner=await login(f.people.owner),lead=await login(f.people.senior),client=await login(f.people.junior),outsider=await login(f.people.reserve)
const stamp=Date.now(),code='S'+String(stamp).slice(-10)
const member=async(userId)=>ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',userId).single()).id
const input={p_workspace_id:f.wsA,p_name:'Setup project '+stamp,p_code:' '+code.toLowerCase()+' ',p_lead_member_id:await member(f.people.senior.userId),p_client_company:' Example studio ',p_client_contact_name:' Client contact ',p_client_email:' CONTACT@EXAMPLE.TEST ',p_client_phone:' +91 9999999999 '}
const stakeholders=ok(await service.from('stakeholders').select('id').eq('workspace_id',f.wsA)).length
const id=ok(await owner.rpc('create_project_with_client',input))[0].out_project_id
const row=()=>service.from('projects').select('*').eq('id',id).single()
let p=ok(await row());assert.equal(p.code,code);assert.equal(p.client_company,'Example studio');assert.equal(p.client_contact_name,'Client contact');assert.equal(p.client_email,'contact@example.test');assert.equal(p.client_phone,'+91 9999999999')
assert.equal(ok(await service.from('stakeholders').select('id').eq('workspace_id',f.wsA)).length,stakeholders)
assert.equal(ok(await outsider.from('projects').select('client_email').eq('id',id)).length,0)
assert((await anon.rpc('create_project_with_client',input)).error)
denied(await outsider.rpc('create_project_with_client',input),'42501')
const before=ok(await service.from('projects').select('id').eq('workspace_id',f.wsA)).length
denied(await owner.rpc('create_project_with_client',{...input,p_name:'Invalid details',p_code:code+'X',p_client_email:'invalid'}),'22023')
assert.equal(ok(await service.from('projects').select('id').eq('workspace_id',f.wsA)).length,before)
console.log('PASS client details round-trip and normalize without invitations; visibility follows project access; invalid details roll back creation')
for(const rpc of ['create_project_with_client','create_project_full']){
 const args={p_workspace_id:f.wsA,p_code:rpc==='create_project_full'?code+'L':code+'N'}
 const results=await Promise.all([1,2].map(n=>owner.rpc(rpc,{...args,p_name:`Concurrent ${rpc} ${stamp} ${n}`})))
 assert.equal(results.filter(r=>!r.error).length,1);assert.equal(results.filter(r=>r.error?.code==='23505').length,1)
}
const other=ok(await owner.rpc('create_project_with_client',{p_workspace_id:f.wsA,p_name:'Other '+stamp}))[0].out_project_id
const edit={p_project_id:other,p_name:'Other renamed',p_code:code.toLowerCase(),p_description:'',p_client_company:'New company',p_client_contact_name:'New contact',p_client_email:'new@example.test',p_client_phone:'123'}
denied(await owner.rpc('update_project_details',edit),'23505')
assert.equal(ok(await service.from('projects').select('name').eq('id',other).single()).name,'Other '+stamp)
ok(await owner.rpc('update_project_details',{...edit,p_code:code+'E'}))
assert.equal(ok(await service.from('projects').select('client_email').eq('id',other).single()).client_email,'new@example.test')
denied(await client.rpc('update_project_details',edit),'42501')
ok(await owner.from('projects').update({archived_at:new Date().toISOString(),status:'archived'}).eq('id',other))
ok(await owner.rpc('create_project_with_client',{p_workspace_id:f.wsA,p_name:'Reused code '+stamp,p_code:code+'E'}))
denied(await owner.from('projects').update({archived_at:null,status:'active'}).eq('id',other),'23505')
ok(await owner.rpc('create_project_with_client',{p_workspace_id:f.wsB,p_name:'Other workspace code '+stamp,p_code:code}))
console.log('PASS concurrent new/legacy creation and edits cannot duplicate codes; workspace scope, archive reuse and restore conflicts are enforced')
const ready=async()=>ok(await owner.rpc('lign_project_ready_for_design',{p_project_id:id}))
assert.equal(await ready(),false)
for(const key of ['asset.create','version.upload','version.publish','file.upload','review.create','approval.request','release.create'])assert.equal(ok(await lead.rpc('lign_has_capability',{p_project_id:id,p_workspace_id:f.wsA,p_capability_key:key})),false,key)
for(const key of ['project.manage_access','requirement.create','project.view'])assert.equal(ok(await lead.rpc('lign_has_capability',{p_project_id:id,p_workspace_id:f.wsA,p_capability_key:key})),true,key)
denied(await lead.from('design_assets').insert({workspace_id:f.wsA,project_id:id,name:'Bypass'}),'23514')
denied(await service.from('design_assets').insert({workspace_id:f.wsA,project_id:id,name:'Privileged bypass'}),'23514')
ok(await lead.rpc('add_project_participant',{p_project_id:id,p_workspace_member_id:await member(f.people.junior.userId),p_role:'approver',p_stakeholder_id:null}))
const pp=ok(await service.from('project_participants').select('id').eq('project_id',id).eq('workspace_member_id',await member(f.people.junior.userId)).single()).id
const doc={disciplines:[],fields:[{id:'objective',label:'Objective',help:'',answer:'Test the setup sequence'},{id:'deliverables',label:'Deliverables',help:'',answer:'An agreed design package'}],items:[{id:'design-quality',kind:'mandatory',title:'Design quality',detail:'Meet the agreed brief',appliesTo:'Whole project',priority:'high',source:'client',ownerProfileId:'',acceptance:'The assigned client accepts a sample',resolution:''}],references:[]}
const read=async()=>ok(await lead.rpc('get_project_brief',{p_project_id:id}))
const transition=async(action)=>ok(await lead.rpc('transition_project_brief',{p_project_id:id,p_expected_version:(await read()).brief.edit_version,p_action:action}))
ok(await lead.rpc('save_project_brief',{p_project_id:id,p_document:doc,p_expected_version:0,p_respondent_participant_id:pp}))
await transition('request_agreement');assert.equal(await ready(),false)
let revision=(await read()).brief.current_revision_id
ok(await client.rpc('respond_project_brief',{p_project_id:id,p_revision_id:revision,p_decision:'changes_requested',p_comment:'Clarify the sample'}));assert.equal(await ready(),false)
await transition('request_agreement');revision=(await read()).brief.current_revision_id
ok(await client.rpc('respond_project_brief',{p_project_id:id,p_revision_id:revision,p_decision:'agreed'}));assert.equal(await ready(),false)
await ensureAcceptedProposal(lead,client,id,pp);assert.equal(await ready(),true)
assert.equal(ok(await lead.rpc('lign_has_capability',{p_project_id:id,p_workspace_id:f.wsA,p_capability_key:'asset.create'})),true)
const asset=ok(await lead.from('design_assets').insert({workspace_id:f.wsA,project_id:id,name:'Agreed design',created_by_profile_id:f.people.senior.userId}).select('id').single())
ok(await lead.rpc('create_draft_version',{p_project_id:id,p_design_asset_id:asset.id}))
await transition('revise');assert.equal(await ready(),true)
ok(await lead.from('design_assets').insert({workspace_id:f.wsA,project_id:id,name:'Work under agreed baseline',created_by_profile_id:f.people.senior.userId}))
console.log('PASS draft, awaiting agreement and requested changes block design APIs and direct writes; brief agreement unlocks proposal preparation, proposal acceptance unlocks design; later revisions preserve the baseline')
writeFileSync(new URL('../../ops/.tmp/project-setup-fixture.json',import.meta.url),JSON.stringify({...f,setupProjectId:id}));chmodSync(new URL('../../ops/.tmp/project-setup-fixture.json',import.meta.url),0o600)
