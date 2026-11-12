// Local-only integration checks. Run studio-leadership.mjs first.
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync, chmodSync } from 'node:fs'
import { createRequire } from 'node:module'
const require=createRequire(new URL('../../app/package.json',import.meta.url))
const { createClient }=require('@supabase/supabase-js')
const config=JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json',import.meta.url)))
const f=JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json',import.meta.url)))
const url=new URL(config.API_URL)
assert(['127.0.0.1','localhost'].includes(url.hostname) && url.port==='58321')
const options={auth:{persistSession:false,autoRefreshToken:false}}
const service=createClient(config.API_URL,config.SERVICE_ROLE_KEY,options)
const anon=createClient(config.API_URL,config.ANON_KEY,options)
const ok=r=>{assert.equal(r.error,null,r.error?.message);return r.data}
const denied=r=>assert.equal(r.error?.code,'42501',r.error?.message ?? 'Unexpected access')
async function login(email) { const c=createClient(config.API_URL,config.ANON_KEY,options);ok(await c.auth.signInWithPassword({email,password:f.password}));return c }
const owner=await login(f.people.owner.email),lead=await login(f.people.leadA.email),senior=await login(f.people.senior.email),junior=await login(f.people.junior.email)
const full=async()=>ok(await owner.rpc('get_access_directory',{p_organization_id:f.orgId}))
const stamp=Date.now(),externals={}
for(const [role,name] of [['reviewer','Structural consultant'],['approver','Client representative']]) {
  const email=`directory-${role}-${stamp}@example.test`
  const user=ok(await service.auth.admin.createUser({email,password:f.password,email_confirm:true})).user
  const c=await login(email)
  const invitation=ok(await senior.rpc('invite_stakeholder',{p_workspace_id:f.wsA,p_project_id:f.pA1,p_email:email,p_role:role,p_display_name:name}))[0]
  if(role==='reviewer') ok(await c.rpc('claim_stakeholder_invitation',{p_token:invitation.out_token}))
  externals[role]={email,name,userId:user.id,stakeholderId:invitation.out_stakeholder_id,client:c}
}
const orgInviteEmail=`directory-staff-${stamp}@example.test`
const secondExternal=ok(await service.from('stakeholders').insert({workspace_id:f.wsB,email:externals.reviewer.email,display_name:externals.reviewer.name,status:'invited'}).select('id').single())
ok(await owner.rpc('add_project_participant',{p_project_id:f.pB1,p_workspace_member_id:null,p_stakeholder_id:secondExternal.id,p_role:'reviewer'}))
ok(await owner.rpc('invite_org_member',{p_organization_id:f.orgId,p_email:orgInviteEmail,p_role:'member'}))
const revokedEmail=`directory-revoked-${stamp}@example.test`
const revoked=ok(await service.from('stakeholders').insert({workspace_id:f.wsA,email:revokedEmail,display_name:'Revoked consultant',status:'revoked',revoked_at:new Date().toISOString()}).select('id').single())
ok(await service.from('project_participants').insert({workspace_id:f.wsA,project_id:f.pA1,stakeholder_id:revoked.id,role:'reviewer',status:'active'}))

let data=await full()
const ownerRow=data.people.find(p=>p.userId===f.people.owner.userId)
assert.equal(ownerRow.organizationRole,'owner')
assert.equal(ownerRow.inheritedAdministration,true)
assert.equal(data.workspaces.length,2)
const reserve=data.people.find(p=>p.userId===f.people.reserve.userId)
assert.equal(reserve.organizationRole,'member')
assert.equal(reserve.inheritedAdministration,false)
assert.deepEqual(reserve.workspaceRoles,[])
assert.deepEqual(reserve.projectRoles,[])
assert(data.pendingInvitations.some(i=>i.email===orgInviteEmail && i.scope==='organization'))
assert(!data.people.some(p=>p.email===revokedEmail))
console.log('PASS owner directory includes studio roles, inherited administration, unassigned staff and pending invitations; revoked access is excluded')

for(const role of ['reviewer','approver']) {
  const row=data.people.find(p=>p.email===externals[role].email)
  assert.equal(row.internal,false)
  assert.equal(row.organizationRole,null)
  assert.deepEqual(row.workspaceRoles,[])
  assert.equal(row.projectRoles.length,role==='reviewer'?2:1)
  const firstProject=row.projectRoles.find(p=>p.projectId===f.pA1)
  assert.equal(firstProject.role,role)
  assert.equal(firstProject.source,'external')
  assert.equal(firstProject.status,role==='reviewer'?'active':'invited')
  if(role==='reviewer') {
    assert.equal(data.people.filter(p=>p.email===externals.reviewer.email).length,1)
    assert.equal(row.projectRoles.find(p=>p.projectId===f.pB1).status,'invited')
  }
}
assert(!JSON.stringify(data).includes('token'))
console.log('PASS external access shows the actual project role and acceptance status without suggesting studio/workspace membership or exposing tokens')

const scoped=ok(await lead.rpc('get_access_directory',{p_workspace_id:f.wsA}))
assert.deepEqual(scoped.workspaces.map(w=>w.id),[f.wsA])
assert(!scoped.people.some(p=>p.userId===f.people.reserve.userId))
assert(scoped.people.flatMap(p=>p.projectRoles).every(p=>p.workspaceId===f.wsA))
assert(scoped.pendingInvitations.every(i=>i.workspaceId===f.wsA))
denied(await lead.rpc('get_access_directory',{p_organization_id:f.orgId}))
denied(await lead.rpc('get_access_directory',{p_workspace_id:f.wsB}))
denied(await owner.rpc('get_access_directory',{p_workspace_id:f.wsA,p_organization_id:'00000000-0000-0000-0000-000000000001'}))
for(const c of [senior,junior,externals.reviewer.client]) denied(await c.rpc('get_access_directory',{p_workspace_id:f.wsA}))
assert((await anon.rpc('get_access_directory',{p_organization_id:f.orgId})).error)
console.log('PASS workspace leads receive only their workspace; project leads, contributors, externals and anonymous callers cannot retrieve leadership directories')

const member=ok(await service.from('workspace_members').select('id').eq('workspace_id',f.wsA).eq('user_id',f.people.junior.userId).single())
ok(await service.from('workspace_members').update({status:'removed',removed_at:new Date().toISOString()}).eq('id',member.id))
data=await full()
assert.deepEqual(data.people.find(p=>p.userId===f.people.junior.userId).projectRoles,[])
ok(await service.from('workspace_members').update({status:'active',removed_at:null}).eq('id',member.id))
ok(await service.from('organization_members').update({status:'removed'}).eq('organization_id',f.orgId).eq('user_id',f.people.junior.userId))
data=await full()
const legacy=data.people.find(p=>p.userId===f.people.junior.userId)
assert.equal(legacy.organizationStatus,'removed')
assert.equal(legacy.workspaceRoles.length,1)
assert.equal(legacy.projectRoles.length,1)
assert.equal(legacy.inheritedAdministration,false)
ok(await service.from('organization_members').update({status:'active'}).eq('organization_id',f.orgId).eq('user_id',f.people.junior.userId))
console.log('PASS directory distinguishes removed membership paths from separate workspace/project assignments that still grant access')

const mixed=ok(await service.from('stakeholders').insert({workspace_id:f.wsA,email:f.people.senior.email,display_name:'Existing staff as consultant',status:'invited'}).select('id').single())
ok(await owner.rpc('add_project_participant',{p_project_id:f.pA2,p_workspace_member_id:null,p_stakeholder_id:mixed.id,p_role:'reviewer'}))
data=await full()
const mixedRows=data.people.filter(p=>p.email===f.people.senior.email)
assert.equal(mixedRows.length,1)
assert.equal(mixedRows[0].internal,true)
assert(mixedRows[0].projectRoles.some(p=>p.projectId===f.pA1 && p.role==='lead' && p.source==='internal'))
assert(mixedRows[0].projectRoles.some(p=>p.projectId===f.pA2 && p.role==='reviewer' && p.source==='external' && p.status==='invited'))
console.log('PASS one person is shown once with separate internal/external assignments and different project roles')
const fixture={...f,externals:Object.fromEntries(Object.entries(externals).map(([k,{client,...v}])=>[k,v])),orgInviteEmail}
const path=new URL('../../ops/.tmp/directory-fixture.json',import.meta.url)
writeFileSync(path,JSON.stringify(fixture));chmodSync(path,0o600)
