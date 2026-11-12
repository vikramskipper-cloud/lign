// Isolated local integration test. No hosted data or email recipients are used.
import assert from 'node:assert/strict'
import { readFileSync, writeFileSync, chmodSync } from 'node:fs'
import { createRequire } from 'node:module'
const require = createRequire(new URL('../../app/package.json', import.meta.url))
const { createClient } = require('@supabase/supabase-js')
const config = JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json', import.meta.url), 'utf8'))
const url = new URL(config.API_URL)
assert(['127.0.0.1', 'localhost'].includes(url.hostname) && url.port === '58321', 'Only the isolated LIGN local backend is allowed')
const options = { auth: { persistSession: false, autoRefreshToken: false } }
const service = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options)
const anon = createClient(config.API_URL, config.ANON_KEY, options)
const ok = (r) => { assert.equal(r.error, null, r.error?.message); return r.data }
const denied = (r, code = '42501') => assert.equal(r.error?.code, code, r.error?.message ?? 'Request unexpectedly succeeded')
const stamp = Date.now()
const password = 'Studio-local-check-42!'
const people = {}
let checks = 0
const pass = (message) => { checks++; console.log('PASS '+message) }
for (const key of ['owner','manager','leadA','leadB','senior','junior','reserve','outsider']) {
  const email = `studio-${key.toLowerCase()}-${stamp}@example.test`
  const user = ok(await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { display_name: `Studio ${key}` } })).user
  const client = createClient(config.API_URL, config.ANON_KEY, options)
  ok(await client.auth.signInWithPassword({ email, password }))
  people[key] = { userId: user.id, email, client }
}
const owner = people.owner.client
const qualify = async (person, company) => ok(await service.from('access_requests').insert({ name: company, email: person.email, phone: '+91 9999999999', company, company_role: 'Owner', team_size: '6-20', status: 'approved', decided_at: new Date().toISOString(), decided_by_profile_id: person.userId }))
await qualify(people.owner, 'Leadership Studio')
const orgId = ok(await owner.rpc('create_organization', { p_name: 'Leadership Studio' }))
for (const key of ['manager','leadA','leadB','senior','junior','reserve']) {
  ok(await owner.rpc('add_org_member', { p_organization_id: orgId, p_user_id: people[key].userId, p_role: key === 'manager' ? 'admin' : 'member' }))
}
const wsA = ok(await owner.rpc('create_workspace_team', { p_organization_id: orgId, p_name: 'Residential Team', p_lead_user_id: people.leadA.userId, p_member_user_ids: [people.senior.userId] }))
const wsB = ok(await people.manager.client.rpc('create_workspace_team', { p_organization_id: orgId, p_name: 'Commercial Team', p_lead_user_id: people.leadB.userId }))
const membership = async (wsId, userId) => ok(await service.from('workspace_members').select('*').eq('workspace_id', wsId).eq('user_id', userId).single())
assert.equal((await membership(wsA, people.owner.userId)).role, 'owner')
assert.equal((await membership(wsA, people.leadA.userId)).role, 'admin')
assert.equal((await membership(wsA, people.senior.userId)).role, 'member')
assert.equal(ok(await service.from('workspace_members').select('id').eq('workspace_id', wsB).eq('user_id', people.owner.userId)).length, 0)
pass('Workspace creation assigns its lead and team atomically while retaining studio ownership')

const beforeCount = ok(await service.from('workspaces').select('id').eq('organization_id', orgId)).length
const invalid = await owner.rpc('create_workspace_team', { p_organization_id: orgId, p_name: 'Invalid Team', p_lead_user_id: people.outsider.userId })
denied(invalid, '23503')
assert.equal(ok(await service.from('workspaces').select('id').eq('organization_id', orgId)).length, beforeCount)
pass('Cross-studio lead assignment fails without leaving a partial workspace')

ok(await people.leadA.client.rpc('assign_workspace_architect', { p_workspace_id: wsA, p_user_id: people.junior.userId, p_role: 'member' }))
denied(await people.leadA.client.rpc('assign_workspace_architect', { p_workspace_id: wsA, p_user_id: people.junior.userId, p_role: 'admin' }))
denied(await people.leadA.client.rpc('invite_workspace_member', { p_workspace_id: wsA, p_email: 'no-invite@example.test', p_role: 'admin' }))
denied(await people.leadA.client.rpc('assign_workspace_architect', { p_workspace_id: wsB, p_user_id: people.reserve.userId, p_role: 'member' }))
denied(await people.leadA.client.rpc('assign_workspace_architect', { p_workspace_id: wsA, p_user_id: people.outsider.userId, p_role: 'member' }), '23503')
denied(await people.junior.client.rpc('assign_workspace_architect', { p_workspace_id: wsA, p_user_id: people.reserve.userId, p_role: 'member' }))
pass('Workspace leads staff their own workspace but cannot appoint leads, escalate roles or cross studio/workspace boundaries')

const seniorMember = (await membership(wsA, people.senior.userId)).id
const juniorMember = (await membership(wsA, people.junior.userId)).id
const createProject = async (client, wsId, name, lead = null) => {
  const result = ok(await client.rpc('create_project_full', { p_workspace_id: wsId, p_name: name, p_lead_member_id: lead, p_client_emails: [] }))
  return (Array.isArray(result) ? result[0] : result).out_project_id
}
const pA1 = await createProject(owner, wsA, 'Garden House', seniorMember)
const pA2 = await createProject(people.leadA.client, wsA, 'Courtyard House')
const pB1 = await createProject(people.leadB.client, wsB, 'Office Tower')
const pB2 = await createProject(people.leadB.client, wsB, 'Retail Pavilion')
const pB3 = await createProject(owner, wsB, 'Owner Commission')
assert.equal((await membership(wsB, people.owner.userId)).role, 'admin')
pass('Multiple projects work per workspace; inherited studio administrators can create work without pre-existing workspace membership')
const participant = async (projectId, memberId) => ok(await service.from('project_participants').select('*').eq('project_id', projectId).eq('workspace_member_id', memberId).single())
assert.equal((await participant(pA1, seniorMember)).role, 'lead')
ok(await owner.rpc('add_project_participant', { p_project_id: pA1, p_workspace_member_id: juniorMember, p_stakeholder_id: null, p_role: 'contributor' }))
const juniorParticipant = await participant(pA1, juniorMember)
ok(await people.senior.client.rpc('change_project_participant_role', { p_participant_id: juniorParticipant.id, p_role: 'reviewer' }))
ok(await people.senior.client.rpc('change_project_participant_role', { p_participant_id: juniorParticipant.id, p_role: 'contributor' }))
denied(await people.senior.client.rpc('create_project_full', { p_workspace_id: wsA, p_name: 'Unauthorised project' }))
pass('Project leads manage their project team; ordinary project roles do not gain workspace administration')

const orgOverview = ok(await owner.rpc('get_studio_overview', { p_organization_id: orgId }))
assert.equal(orgOverview.workspaces.length, 2)
assert.equal(orgOverview.workspaces.flatMap((w) => w.projects).length, 5)
assert(orgOverview.activity.some((a) => a.projectId === pB3))
const aOverview = ok(await people.leadA.client.rpc('get_studio_overview', { p_workspace_id: wsA }))
assert.deepEqual(new Set(aOverview.workspaces[0].projects.map((p) => p.id)), new Set([pA1,pA2]))
assert(aOverview.workspaces[0].projects.find((p) => p.id === pA1).leads.some((l) => l.userId === people.senior.userId))
assert(aOverview.activity.every((a) => a.workspaceId === wsA))
denied(await people.leadA.client.rpc('get_studio_overview', { p_organization_id: orgId }))
denied(await people.leadA.client.rpc('get_studio_overview', { p_workspace_id: wsB }))
denied(await people.junior.client.rpc('get_studio_overview', { p_workspace_id: wsA }))
denied(await people.outsider.client.rpc('get_studio_overview', { p_organization_id: orgId }))
assert((await anon.rpc('get_studio_overview', { p_organization_id: orgId })).error)
pass('Owner overview includes all work; workspace-lead overview includes every local project and no other workspace data')
assert.equal(ok(await people.junior.client.from('projects').select('id')).length, 1)
assert.equal(ok(await people.reserve.client.from('workspaces').select('id')).length, 0)
assert.equal(ok(await people.outsider.client.from('projects').select('id')).length, 0)
pass('Junior architects see only assigned projects; unassigned colleagues and outsiders cannot inspect studio work')

const seniorParticipant = await participant(pA1, seniorMember)
denied(await owner.rpc('change_project_participant_role', { p_participant_id: seniorParticipant.id, p_role: 'contributor' }), '23514')
denied(await owner.rpc('remove_project_participant', { p_participant_id: seniorParticipant.id }), '23514')
denied(await owner.rpc('remove_workspace_member', { p_workspace_member_id: seniorMember }), '23514')
assert.equal((await membership(wsA, people.senior.userId)).status, 'active')
ok(await owner.rpc('change_project_participant_role', { p_participant_id: juniorParticipant.id, p_role: 'lead' }))
const concurrent = await Promise.all([
  owner.rpc('change_project_participant_role', { p_participant_id: seniorParticipant.id, p_role: 'contributor' }),
  people.manager.client.rpc('change_project_participant_role', { p_participant_id: juniorParticipant.id, p_role: 'contributor' }),
])
assert.equal(concurrent.filter((r) => !r.error).length, 1)
assert.equal(concurrent.filter((r) => r.error?.code === '23514').length, 1)
assert.equal(ok(await service.from('project_participants').select('id').eq('project_id', pA1).eq('role','lead').eq('status','active')).length, 1)
ok(await owner.rpc('change_project_participant_role', { p_participant_id: seniorParticipant.id, p_role: 'lead' }))
ok(await owner.rpc('change_project_participant_role', { p_participant_id: juniorParticipant.id, p_role: 'contributor' }))
pass('Last-lead protection covers role changes, project removal, workspace removal and concurrent demotions')

const leadMember = (await membership(wsA, people.leadA.userId)).id
denied(await people.leadA.client.rpc('change_workspace_member_role', { p_workspace_member_id: juniorMember, p_role: 'admin' }))
ok(await owner.rpc('change_workspace_member_role', { p_workspace_member_id: juniorMember, p_role: 'admin' }))
ok(await owner.rpc('change_workspace_member_role', { p_workspace_member_id: juniorMember, p_role: 'member' }))
denied(await people.leadA.client.rpc('remove_workspace_member', { p_workspace_member_id: leadMember }))
pass('Studio ownership controls workspace leadership; delegated leads cannot remove or demote themselves')
const colleagueInvite = ok(await owner.rpc('invite_workspace_member', { p_workspace_id: wsA, p_email: people.outsider.email, p_role: 'member' }))
const colleagueToken = (Array.isArray(colleagueInvite) ? colleagueInvite[0] : colleagueInvite).out_token
assert.ok(colleagueToken)
ok(await people.outsider.client.rpc('accept_invitation', { p_token: colleagueToken }))
const joinedStudio = ok(await service.from('organization_members').select('role,status').eq('organization_id',orgId).eq('user_id',people.outsider.userId).single())
assert.deepEqual(joinedStudio,{role:'member',status:'active'})
assert.equal(ok(await service.from('organization_members').select('role').eq('organization_id',orgId).eq('user_id',people.owner.userId).single()).role,'owner')
denied(await people.outsider.client.rpc('get_studio_overview', { p_organization_id: orgId }))
pass('Accepted workspace invitations join the studio without granting studio leadership or overwriting owner roles')
const fixture = { orgId, wsA, wsB, pA1, pA2, pB1, pB2, pB3, password, people: Object.fromEntries(Object.entries(people).map(([key,p]) => [key, { userId:p.userId,email:p.email }])) }
writeFileSync(new URL('../../ops/.tmp/leadership-fixture.json', import.meta.url),JSON.stringify(fixture))
chmodSync(new URL('../../ops/.tmp/leadership-fixture.json', import.meta.url),0o600)
console.log(`${checks} studio integration checks passed; local fixtures saved for browser verification.`)
