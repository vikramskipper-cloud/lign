// Local-only requirements hierarchy and agreement-history checks.
import assert from 'node:assert/strict'
import {readFileSync,writeFileSync,chmodSync} from 'node:fs'
import {createRequire} from 'node:module'
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const url=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(url.hostname)&&url.port==='58321')
const opts={auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(i,o)=>fetch(i,{...o,signal:AbortSignal.timeout(20000)})}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,opts),anon=createClient(config.API_URL,config.ANON_KEY,opts)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data},denied=(r,c='42501')=>assert.equal(r.error?.code,c,r.error?.message??'Unexpected success')
async function login(p){const c=createClient(config.API_URL,config.ANON_KEY,opts);ok(await c.auth.signInWithPassword({email:p.email,password:f.password}));return c}
const owner=await login(f.people.owner),lead=await login(f.people.senior),junior=await login(f.people.junior),outsider=await login(f.people.reserve)
const project=f.pA1
const saveArea=async(name,parent=null,kind=parent?'Zone':'Space',id=null)=>ok(await lead.rpc('save_project_area',{p_project_id:project,p_name:name,p_kind:kind,p_parent_id:parent,p_area_id:id,p_description:'Local requirement area'}))
const space=await saveArea('Living room'),zone=await saveArea('Seating',space),sibling=await saveArea('Dining',space),other=await saveArea('Kitchen')
const cross=ok(await owner.rpc('save_project_area',{p_project_id:f.pA2,p_name:'Other project'}))
denied(await lead.rpc('save_project_area',{p_project_id:project,p_name:'Cross project',p_parent_id:cross}),'23503')
denied(await junior.rpc('save_project_area',{p_project_id:project,p_name:'Escalation'}))
denied(await outsider.rpc('get_project_areas',{p_project_id:project}))
assert((await anon.rpc('get_project_areas',{p_project_id:project})).error)
assert.equal(ok(await junior.rpc('get_project_areas',{p_project_id:project})).canManage,false)
assert((await lead.from('project_areas').insert({project_id:project,workspace_id:f.wsA,name:'Direct bypass'})).error)
const collisions=await Promise.all(['Study',' study '].map(p_name=>lead.rpc('save_project_area',{p_project_id:project,p_name})))
assert.equal(collisions.filter(r=>!r.error).length,1);assert.equal(collisions.filter(r=>r.error?.code==='23505').length,1)
denied(await service.from('project_areas').update({parent_area_id:zone}).eq('id',space),'23514')
let deep=space;for(let depth=2;depth<=8;depth++)deep=await saveArea('Level '+depth,deep,'Component')
denied(await lead.rpc('save_project_area',{p_project_id:project,p_name:'Too deep',p_parent_id:deep}),'23514')
const unused=await saveArea('Unused');ok(await lead.rpc('archive_project_area',{p_area_id:unused}));denied(await lead.rpc('archive_project_area',{p_area_id:space}),'23514')
console.log('PASS optional nested areas and custom labels; leadership-only writes, tenant isolation, sibling uniqueness, immutable parents, depth limit and safe archiving')
const create=async(title,ids=[],parent=null)=>ok(await lead.rpc('create_requirement_with_areas',{p_project_id:project,p_workspace_id:f.wsA,p_title:title,p_area_ids:ids,p_parent_requirement_id:parent}))[0].out_requirement_id
const global=await create('Overall budget'),spaceReq=await create('Living room capacity',[space]),zoneReq=await create('Seating clearances',[zone]),otherReq=await create('Kitchen ventilation',[other]),diningReq=await create('Dining capacity',[sibling]),multi=await create('Shared finish',[zone,other]),child=await create('Seating accessibility',[],zoneReq)
const list=async(args={})=>ok(await lead.rpc('list_area_requirements',{p_project_id:project,...args}))
const zoneRows=(await list({p_area_id:zone})).rows.map(r=>r.id)
for(const id of [global,spaceReq,zoneReq,multi,child])assert(zoneRows.includes(id))
for(const id of [otherReq,diningReq])assert(!zoneRows.includes(id))
assert.equal((await list({p_project_only:true})).rows.length,1)
assert((await list({p_area_id:space})).rows.some(r=>r.id===diningReq))
assert(!(await list({p_area_id:space,p_include_descendants:false})).rows.some(r=>r.id===zoneReq))
assert.deepEqual(ok(await lead.rpc('get_requirement_areas',{p_requirement_id:child})).areas.map(a=>a.id),[zone])
denied(await lead.rpc('set_requirement_areas',{p_requirement_id:child,p_area_ids:[other]}),'23514')
denied(await outsider.rpc('set_requirement_areas',{p_requirement_id:global,p_area_ids:[zone]}))
denied(await lead.rpc('set_requirement_areas',{p_requirement_id:global,p_area_ids:[cross]}),'23503')
const before=ok(await service.from('requirements').select('id').eq('project_id',project)).length
denied(await createResult('Invalid atomic scope',[cross]),'23503')
async function createResult(title,ids){return lead.rpc('create_requirement_with_areas',{p_project_id:project,p_workspace_id:f.wsA,p_title:title,p_area_ids:ids})}
assert.equal(ok(await service.from('requirements').select('id').eq('project_id',project)).length,before)
assert((await lead.from('requirement_areas').insert({requirement_id:global,area_id:zone,project_id:project,workspace_id:f.wsA})).error)
denied(await service.from('requirement_areas').insert({requirement_id:global,area_id:cross,project_id:project,workspace_id:f.wsA}),'23503')
let cursor=null,ids=[];do{const page=await list({p_limit:2,p_after:cursor});ids.push(...page.rows.map(r=>r.id));cursor=page.nextCursor}while(cursor)
assert.equal(new Set(ids).size,7);assert.equal(ids.length,7)
console.log('PASS project-wide and ancestor inheritance, child requirement inheritance, multi-area assignments, server pagination and atomic invalid-scope rollback')
const pp=ok(await service.from('project_participants').select('id').eq('project_id',project).eq('workspace_member_id',ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',f.people.junior.userId).single()).id).single()).id
ok(await lead.rpc('change_project_participant_role',{p_participant_id:pp,p_role:'approver'}))
const document={disciplines:['interiors'],fields:[{id:'objective',label:'Objective',help:'',answer:'Create a comfortable home'},{id:'deliverables',label:'Deliverables',help:'',answer:'An agreed layout and sample'}],items:[{id:'seating',kind:'mandatory',title:'Seat six people',detail:'Comfortable seating',appliesTo:'Main sofa arrangement',areaIds:[zone],areaSnapshot:[{id:zone,path:'Spoofed label'}],priority:'high',source:'client',ownerProfileId:'',acceptance:'Count six seats',resolution:''}],references:[]}
const read=async()=>ok(await lead.rpc('get_project_brief',{p_project_id:project})),save=async(doc,client=lead)=>ok(await client.rpc('save_project_brief',{p_project_id:project,p_document:doc,p_expected_version:(await read()).brief?.edit_version??0,p_respondent_participant_id:pp})),transition=async(action)=>ok(await lead.rpc('transition_project_brief',{p_project_id:project,p_expected_version:(await read()).brief.edit_version,p_action:action}))
await save(document)
assert.equal((await read()).brief.document.items[0].areaSnapshot[0].path,'Living room / Seating')
const invalid=structuredClone(document);invalid.items[0].areaIds=[cross]
denied(await junior.rpc('save_project_brief',{p_project_id:project,p_document:invalid,p_expected_version:(await read()).brief.edit_version,p_respondent_participant_id:pp}),'23503')
await saveArea('Sitting area',space,'Zone',zone);await transition('request_agreement')
const revision=(await read()).brief.current_revision_id
assert.equal((await read()).revisions[0].document.items[0].areaSnapshot[0].path,'Living room / Sitting area')
denied(await lead.rpc('save_project_area',{p_project_id:project,p_name:'Changed during agreement',p_area_id:zone,p_parent_id:space}),'23514')
ok(await junior.rpc('respond_project_brief',{p_project_id:project,p_revision_id:revision,p_decision:'agreed'}))
await transition('revise');await saveArea('Seating zone renamed',space,'Zone',zone)
assert.equal(ok(await lead.rpc('generate_brief_requirements',{p_project_id:project,p_revision_id:revision})),1)
assert.equal(ok(await lead.rpc('generate_brief_requirements',{p_project_id:project,p_revision_id:revision})),0)
const generated=ok(await service.from('project_brief_requirement_links').select('requirement_id').eq('revision_id',revision).single()).requirement_id
assert.deepEqual(ok(await lead.rpc('get_requirement_areas',{p_requirement_id:generated})).areas.map(a=>a.id),[zone])
assert(ok(await service.from('requirements').select('description').eq('id',generated).single()).description.includes('Living room / Sitting area'))
assert.equal((await read()).revisions[0].document.items[0].areaSnapshot[0].path,'Living room / Sitting area')
console.log('PASS brief scopes validate project identity, ignore forged labels, refresh at agreement, freeze historical paths and generate scoped requirement drafts exactly once')
writeFileSync(new URL('../../ops/.tmp/areas-fixture.json',import.meta.url),JSON.stringify({...f,space,zone,zoneReq,child,revision}));chmodSync(new URL('../../ops/.tmp/areas-fixture.json',import.meta.url),0o600)
