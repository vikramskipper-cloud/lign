// Local-only owner onboarding and organisation-scoped defaults. No production users or emails.
import assert from 'node:assert/strict'
import {readFileSync,writeFileSync,chmodSync} from 'node:fs'
import {createRequire} from 'node:module'
const require=createRequire(new URL('../../app/package.json',import.meta.url)),{createClient}=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url))),f=JSON.parse(readFileSync(new URL('../../ops/.tmp/planning-fixture.json',import.meta.url)))
const host=new URL(config.API_URL);assert(['localhost','127.0.0.1'].includes(host.hostname)&&host.port==='58321')
const opts={auth:{persistSession:false,autoRefreshToken:false}},service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,opts),anon=createClient(config.API_URL,config.ANON_KEY,opts)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data},deny=(r,code='42501')=>assert.equal(r.error?.code,code,r.error?.message??'Unexpected success'),stamp=Date.now(),password='Org-profile-local-42!'
async function founder(label){const email=`org-${label}-${stamp}@example.test`,u=ok(await service.auth.admin.createUser({email,password,email_confirm:true})).user;ok(await service.from('access_requests').insert({name:'Profile owner',email,phone:'+91 9999999999',company:'Profile Studio '+label,company_role:'Owner',team_size:'2-5',status:'approved',decided_at:new Date().toISOString(),decided_by_profile_id:u.id}));const c=createClient(config.API_URL,config.ANON_KEY,opts);ok(await c.auth.signInWithPassword({email,password}));return {c,email,u}}
const person=await founder('owner'),owner=person.c
assert.equal(ok(await owner.rpc('get_activation_design_profile')).needsProfile,true)
deny(await owner.rpc('complete_approved_access_profile',{p_disciplines:['medicine']}),'22023');assert.equal(ok(await owner.from('organizations').select('id')).length,0)
const ws=ok(await owner.rpc('complete_approved_access_profile',{p_disciplines:['interiors','architecture']})),org=ok(await owner.from('workspaces').select('organization_id').eq('id',ws).single()).organization_id
let profile=ok(await owner.rpc('get_organization_design_profile',{p_organization_id:org}));assert.deepEqual(profile.disciplines,['architecture','interiors']);assert.equal(profile.version,1);assert.equal(profile.configured,true)
assert.equal(ok(await owner.rpc('get_activation_design_profile')).needsProfile,false)
assert.equal(ok(await owner.rpc('complete_approved_access_profile',{p_disciplines:['fashion']})),ws);assert.deepEqual(ok(await owner.rpc('get_organization_design_profile',{p_organization_id:org})).disciplines,['architecture','interiors'])
const createProject=async name=>{const r=ok(await owner.rpc('create_project_full',{p_workspace_id:ws,p_name:name,p_client_emails:[]}));return (Array.isArray(r)?r[0]:r).out_project_id}
const project=await createProject('Profile brief browser '+stamp)
assert.deepEqual(ok(await owner.rpc('get_project_brief',{p_project_id:project})).organizationDisciplines,['architecture','interiors'])
const savedDocument={disciplines:['architecture'],fields:[{id:'objective',label:'Objective',help:'',answer:'Keep this answer'},{id:'deliverables',label:'Deliverables',help:'',answer:'Design package'}],items:[],references:[]}
ok(await owner.rpc('save_project_brief',{p_project_id:project,p_document:savedDocument,p_expected_version:0,p_respondent_participant_id:null}))
ok(await owner.rpc('save_organization_design_profile',{p_organization_id:org,p_disciplines:['fashion'],p_expected_version:1}))
assert.deepEqual(ok(await owner.rpc('get_project_brief',{p_project_id:project})).brief.document,savedDocument)
deny(await owner.rpc('save_organization_design_profile',{p_organization_id:org,p_disciplines:['product'],p_expected_version:1}),'PT409')
for(const ids of [['invalid'],[null],null])deny(await owner.rpc('save_organization_design_profile',{p_organization_id:org,p_disciplines:ids,p_expected_version:2}),'22023')
const member=createClient(config.API_URL,config.ANON_KEY,opts);ok(await member.auth.signInWithPassword({email:f.people.reserve.email,password:f.password}));deny(await member.rpc('get_organization_design_profile',{p_organization_id:org}));deny(await member.rpc('get_project_brief',{p_project_id:project}))
ok(await owner.rpc('add_org_member',{p_organization_id:org,p_user_id:f.people.reserve.userId,p_role:'member'}))
assert.equal(ok(await member.rpc('get_organization_design_profile',{p_organization_id:org})).canManage,false)
deny(await member.rpc('save_organization_design_profile',{p_organization_id:org,p_disciplines:['product'],p_expected_version:2}));assert((await anon.rpc('get_activation_design_profile')).error)
const member2=createClient(config.API_URL,config.ANON_KEY,opts);ok(await member2.auth.signInWithPassword({email:f.people.client.email,password:f.password}));assert.equal(ok(await member2.rpc('get_activation_design_profile')).needsProfile,false);assert.equal(ok(await member2.rpc('complete_approved_access_profile',{p_disciplines:['product']})),null)
const general=await founder('general'),generalWs=ok(await general.c.rpc('create_workspace_with_design_profile',{p_name:'General Studio',p_slug:'general-studio',p_disciplines:[]})),generalOrg=ok(await general.c.from('workspaces').select('organization_id').eq('id',generalWs).single()).organization_id
assert.deepEqual(ok(await general.c.rpc('get_organization_design_profile',{p_organization_id:generalOrg})).disciplines,[])
// Prepare the isolated owner UI fixture with its new default and an untouched project.
const newProject=await createProject('New inherited brief '+stamp)
const file=new URL('../../ops/.tmp/org-profile-fixture.json',import.meta.url);writeFileSync(file,JSON.stringify({email:person.email,password,org,ws,project,newProject,member:f.people.reserve.email,memberPassword:f.password}));chmodSync(file,0o600)
console.log('PASS account creation captures multi-discipline defaults atomically; retries preserve configuration; invalid activation rolls back; general design and first-run workspace creation supported')
console.log('PASS owner/admin-only updates, stale version checks, tenant/member/guest isolation, new-brief defaults and saved brief preservation')
