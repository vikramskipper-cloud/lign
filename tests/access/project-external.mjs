// Mutating integration test: isolated LIGN backend and synthetic accounts only.
// Run studio-leadership.mjs first to prepare the studio/project fixtures.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const require = createRequire(new URL('../../app/package.json', import.meta.url))
const { createClient } = require('@supabase/supabase-js')
const config = JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json', import.meta.url)))
const f = JSON.parse(readFileSync(new URL('../../ops/.tmp/leadership-fixture.json', import.meta.url)))
const url = new URL(config.API_URL)
assert(['localhost','127.0.0.1'].includes(url.hostname) && url.port === '58321')
const options = { auth: { persistSession:false, autoRefreshToken:false } }
const service = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options)
const anon = createClient(config.API_URL, config.ANON_KEY, options)
const ok = (r) => { assert.equal(r.error,null,r.error?.message); return r.data }
const denied = (r) => assert.equal(r.error?.code,'42501',r.error?.message ?? 'Unexpected permission grant')
async function login(person) {
  const c = createClient(config.API_URL,config.ANON_KEY,options)
  ok(await c.auth.signInWithPassword({email:person.email,password:f.password}))
  return c
}
const lead = await login(f.people.senior)
const workspaceLead = await login(f.people.leadA)
const junior = await login(f.people.junior)
const stamp = Date.now()
const args = (email,role='reviewer',project=f.pA1,workspace=f.wsA) => ({ p_workspace_id:workspace,p_project_id:project,p_email:email,p_role:role,p_display_name:'External consultant' })
const invite = async (c,a) => { const rows=ok(await c.rpc('invite_stakeholder',a));return rows[0] }
for (const a of [
  args(`other-project-${stamp}@example.test`,'reviewer',f.pA2),
  args(`other-workspace-${stamp}@example.test`,'reviewer',f.pB1,f.wsB),
  args(`forged-workspace-${stamp}@example.test`,'reviewer',f.pA1,f.wsB),
]) denied(await lead.rpc('invite_stakeholder',a))
for (const role of ['lead','contributor','observer']) denied(await lead.rpc('invite_stakeholder',args(`escalation-${role}-${stamp}@example.test`,role)))
denied(await junior.rpc('invite_stakeholder',args(`junior-${stamp}@example.test`)))
assert((await anon.rpc('invite_stakeholder',args(`anon-${stamp}@example.test`))).error)
assert.equal(ok(await service.from('stakeholders').select('id').like('email',`%${stamp}@example.test`)).length,0)
console.log('PASS project lead invites stay within their project; contributors, anonymous calls and privileged invite roles are denied without partial records')

for (const role of ['reviewer','approver']) {
  const email=`external-${role}-${stamp}@example.test`
  const user=ok(await service.auth.admin.createUser({email,password:f.password,email_confirm:true})).user
  const external=await login({email})
  const i=await invite(lead,args(email,role))
  ok(await lead.rpc('queue_invitation_email',{p_token:i.out_token}))
  const queue=ok(await service.from('email_outbox').select('template,status,to_email').eq('dedupe_key',`invitation:${i.out_invitation_id}`).single())
  assert.equal(queue.template,'stakeholder_invitation')
  assert.equal(queue.status,'queued')
  assert.equal(queue.to_email,email)
  denied(await junior.rpc('claim_stakeholder_invitation',{p_token:i.out_token}))
  ok(await external.rpc('claim_stakeholder_invitation',{p_token:i.out_token}))
  denied(await external.rpc('claim_stakeholder_invitation',{p_token:i.out_token}))
  assert.deepEqual(ok(await external.from('projects').select('id')).map(p=>p.id),[f.pA1])
  assert.equal(ok(await service.from('workspace_members').select('id').eq('user_id',user.id)).length,0)
  assert.equal(ok(await service.from('organization_members').select('id').eq('user_id',user.id)).length,0)
  for (const capability of ['project.view','comment.create',role==='reviewer'?'review.participate':'approval.respond']) {
    assert.equal(ok(await external.rpc('lign_has_capability',{p_project_id:f.pA1,p_workspace_id:f.wsA,p_capability_key:capability})),true)
  }
  denied(await external.rpc('invite_stakeholder',args(`nested-${role}-${stamp}@example.test`)))
  assert.equal(ok(await lead.rpc('lign_has_capability',{p_project_id:null,p_workspace_id:f.wsA,p_capability_key:'stakeholder.invite'})),false)
  console.log(`PASS project lead invites ${role}; email queues, correct recipient accepts once, and access stays scoped with comments and ${role==='reviewer'?'review':'approval'} permissions`)
}

const revokedEmail=`revoked-${stamp}@example.test`
const revoked=ok(await service.from('stakeholders').insert({workspace_id:f.wsA,email:revokedEmail,display_name:'Protected identity',status:'revoked',revoked_at:new Date().toISOString()}).select('id').single())
denied(await lead.rpc('invite_stakeholder',args(revokedEmail)))
assert.equal(ok(await service.from('stakeholders').select('status').eq('id',revoked.id).single()).status,'revoked')
assert.equal(ok(await service.from('project_participants').select('id').eq('stakeholder_id',revoked.id)).length,0)
await invite(workspaceLead,args(revokedEmail))
await invite(workspaceLead,args(`workspace-invite-${stamp}@example.test`,'contributor'))
console.log('PASS workspace leadership retains existing invitation/restoration authority; project leads cannot undo workspace revocation')

const sharedEmail=`shared-${stamp}@example.test`
const shared=ok(await service.from('stakeholders').insert({workspace_id:f.wsA,email:sharedEmail,display_name:'Existing consultant identity',status:'active'}).select('id').single())
ok(await workspaceLead.rpc('add_project_participant',{p_project_id:f.pA2,p_workspace_member_id:null,p_stakeholder_id:shared.id,p_role:'reviewer'}))
await invite(lead,args(sharedEmail))
assert.equal(ok(await service.from('stakeholders').select('display_name').eq('id',shared.id).single()).display_name,'Existing consultant identity')
assert.equal(ok(await service.from('project_participants').select('id').eq('project_id',f.pA2).eq('stakeholder_id',shared.id).eq('status','active')).length,1)
console.log('PASS inviting an existing consultant preserves their shared identity and other project assignments')
