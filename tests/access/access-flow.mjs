// Run against the disposable local stack only. Never accepts a hosted URL.
// supabase status --output json > ops/.tmp/access-local.json
// node tests/access/access-flow.mjs
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const require = createRequire(new URL('../../app/package.json', import.meta.url))
const { createClient } = require('@supabase/supabase-js')
const config = JSON.parse(readFileSync(new URL('../../ops/.tmp/access-local.json', import.meta.url), 'utf8'))
const url = new URL(config.API_URL)
assert.ok(['127.0.0.1', 'localhost'].includes(url.hostname) && url.port === '58321', 'Tests require the isolated LIGN local stack')
const options = { auth: { persistSession: false, autoRefreshToken: false } }
const service = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options)
const anon = createClient(config.API_URL, config.ANON_KEY, options)
const client = () => createClient(config.API_URL, config.ANON_KEY, options)
const ok = (result) => { assert.equal(result.error, null, result.error?.message); return result.data }
const stamp = Date.now()
const email = (name) => `${name}-${stamp}@example.test`
const password = 'Lign-local-test-92!'
let checks = 0
const pass = (label) => { checks++; console.log(`PASS ${label}`) }
const newAccount = async (name) => ok(await service.auth.admin.createUser({ email: email(name), password, email_confirm: true })).user

const signup = await anon.auth.signUp({ email: email('unapproved'), password })
assert.ok(signup.error && /signup.*disabled|signups.*not allowed/i.test(signup.error.message))
pass('Auth server rejects public self-registration')
const adminUser = await newAccount('staff')
ok(await service.from('platform_admins').insert({ profile_id: adminUser.id }))
const admin = client()
ok(await admin.auth.signInWithPassword({ email: email('staff'), password }))
const outsider = client()
await newAccount('outsider')
ok(await outsider.auth.signInWithPassword({ email: email('outsider'), password }))

const input = { p_name: 'Ada Owner', p_email: email('owner'), p_phone: '+91 9999999999', p_company: 'Example Studio', p_company_role: 'Founder', p_team_size: '2-5' }
for (const field of ['p_name', 'p_email', 'p_phone', 'p_company', 'p_company_role', 'p_team_size']) {
  const invalid = await anon.rpc('submit_access_request', { ...input, [field]: '' })
  assert.ok(invalid.error, `${field} must be required`)
}
pass('All six request fields are required by the backend')
ok(await anon.rpc('submit_access_request', input))
ok(await anon.rpc('submit_access_request', { ...input, p_email: input.p_email.toUpperCase(), p_name: 'Ada Updated' }))
const requests = ok(await service.from('access_requests').select('*').eq('email', input.p_email))
assert.equal(requests.length, 1)
assert.equal(requests[0].name, 'Ada Updated')
assert.equal(requests[0].company, 'Example Studio')
const requestId = requests[0].id
assert.equal(ok(await anon.from('access_requests').select('id')).length, 0)
assert.equal(ok(await outsider.from('access_requests').select('id')).length, 0)
pass('Public submission persists company, deduplicates by email, and protects the review queue')
assert.ok((await outsider.rpc('decide_access_request', { p_request_id: requestId, p_approve: true })).error)
assert.equal(ok(await outsider.rpc('complete_approved_access')), null)
assert.ok((await outsider.rpc('create_organization', { p_name: 'Unapproved Company' })).error)
pass('Non-staff cannot approve; unapproved users cannot found an organisation')
ok(await admin.rpc('decide_access_request', { p_request_id: requestId, p_approve: true }))
assert.ok((await admin.rpc('decide_access_request', { p_request_id: requestId, p_approve: true })).error)
const queued = ok(await service.from('email_outbox').select('*').eq('dedupe_key', `access-decision:${requestId}`).single())
assert.equal(queued.template, 'access_request_approved')
assert.equal(queued.payload.request_id, requestId)
assert.ok((await admin.from('email_outbox').select('payload')).error)
pass('Approval is staff-only, recorded once, and queues a protected welcome job')

const generated = ok(await service.auth.admin.generateLink({ type: 'invite', email: input.p_email, options: { data: { display_name: input.p_name } } }))
assert.match(generated.properties.hashed_token, /^[a-f0-9]{56}$/)
const owner = client()
ok(await owner.auth.verifyOtp({ type: 'invite', token_hash: generated.properties.hashed_token }))
ok(await owner.auth.updateUser({ password }))
const activations = await Promise.all([owner.rpc('complete_approved_access'), owner.rpc('complete_approved_access')])
const workspaceId = ok(activations[0])
assert.equal(ok(activations[1]), workspaceId)
assert.ok(workspaceId)
assert.equal(ok(await owner.rpc('complete_approved_access')), workspaceId)
const workspace = ok(await owner.from('workspaces').select('id, organization_id, name').eq('id', workspaceId).single())
assert.equal(workspace.name, input.p_company)
const membership = ok(await owner.from('organization_members').select('role').eq('organization_id', workspace.organization_id).eq('user_id', generated.user.id).single())
assert.equal(membership.role, 'owner')
assert.equal(ok(await service.from('organizations').select('id').eq('id', workspace.organization_id)).length, 1)
ok(await service.from('access_requests').insert({ name: 'Legacy duplicate', email: input.p_email, phone: input.p_phone,
  company: 'Legacy Studio', company_role: input.p_company_role, team_size: input.p_team_size,
  status: 'approved', decided_at: new Date().toISOString(), decided_by_profile_id: adminUser.id }))
assert.equal(ok(await owner.rpc('complete_approved_access')), workspaceId)
pass('Concurrent activation and historical duplicate approvals preserve one company, workspace, and owner')
ok(await owner.auth.signOut())
ok(await owner.auth.signInWithPassword({ email: input.p_email, password }))
assert.equal(ok(await owner.from('workspaces').select('id').eq('id', workspaceId)).length, 1)
assert.ok((await owner.auth.verifyOtp({ type: 'invite', token_hash: generated.properties.hashed_token })).error)
pass('Owner can sign in normally; welcome token cannot be reused')

const existing = ok(await service.auth.admin.generateLink({ type: 'recovery', email: input.p_email }))
ok(await owner.auth.verifyOtp({ type: 'recovery', token_hash: existing.properties.hashed_token }))
assert.equal(ok(await owner.rpc('complete_approved_access')), workspaceId)
pass('Recovery for an existing applicant preserves the same organisation')

assert.ok((await anon.rpc('claim_email_batch')).error)
assert.ok((await admin.rpc('claim_email_batch')).error)
const claimed = ok(await service.rpc('claim_email_batch', { p_outbox_id: queued.id }))
assert.equal(claimed.length, 1)
assert.equal(claimed[0].attempts, 1)
assert.equal(ok(await service.rpc('claim_email_batch', { p_outbox_id: queued.id })).length, 0)
ok(await service.from('email_outbox').update({ status: 'sent', sent_at: new Date().toISOString(), payload: {}, locked_until: null, lock_token: null }).eq('id', queued.id))
ok(await admin.rpc('resend_access_welcome', { p_request_id: requestId }))
const resent = ok(await service.from('email_outbox').select('*').eq('id', queued.id).single())
assert.equal(resent.status, 'queued')
assert.equal(resent.attempts, 0)
assert.equal(resent.payload.activation_url, undefined)
assert.ok((await outsider.rpc('resend_access_welcome', { p_request_id: requestId })).error)
pass('Worker leases prevent duplicate sends; staff can resend without exposing tokens')

const orgInvite = ok(await owner.rpc('invite_org_member', { p_organization_id: workspace.organization_id, p_email: email('teammate'), p_role: 'member' }))
// RPC returns a single row array, with a server-issued invitation token.
const invitation = Array.isArray(orgInvite) ? orgInvite[0] : orgInvite
assert.ok(invitation.out_token)
ok(await owner.rpc('queue_invitation_email', { p_token: invitation.out_token }))
const invitedLink = ok(await service.auth.admin.generateLink({ type: 'invite', email: email('teammate') }))
const teammate = client()
ok(await teammate.auth.verifyOtp({ type: 'invite', token_hash: invitedLink.properties.hashed_token }))
ok(await teammate.auth.updateUser({ password }))
assert.equal(ok(await teammate.rpc('complete_approved_access')), null)
ok(await teammate.auth.signOut())
ok(await teammate.auth.signInWithPassword({ email: email('teammate'), password }))
ok(await teammate.rpc('accept_org_invitation', { p_token: invitation.out_token }))
assert.equal(ok(await teammate.from('organization_members').select('role').eq('user_id', invitedLink.user.id).single()).role, 'member')
pass('Invited teammates activate and accept invitations with public signup disabled')
console.log(`${checks} integration checks passed; no hosted services or email recipients were used.`)
