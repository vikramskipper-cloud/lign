// deno test -A --node-modules-dir=auto --no-lock tests/access/email-worker.test.ts
// Uses a real isolated local Supabase API, and intercepts every provider call.
import { createClient } from 'npm:@supabase/supabase-js@2.109.0'
import { handleEmailRequest } from '../../supabase/functions/send-emails/handler.ts'

const assert = (condition: unknown, message: string) => { if (!condition) throw new Error(message) }
const config = JSON.parse(await Deno.readTextFile(new URL('../../ops/.tmp/access-local.json', import.meta.url)))
const url = new URL(config.API_URL)
assert(['127.0.0.1', 'localhost'].includes(url.hostname) && url.port === '58321', 'Only the local LIGN stack is allowed')
Deno.env.set('SUPABASE_URL', config.API_URL)
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', config.SERVICE_ROLE_KEY)
Deno.env.set('EMAIL_FROM', 'welcome@example.test')
Deno.env.set('APP_URL', 'http://127.0.0.1:5179')
Deno.env.set('EMAIL_WORKER_TOKEN', 'local-worker-secret')
Deno.env.set('SENDGRID_API_KEY', 'local-fake-key')
const options = { auth: { persistSession: false, autoRefreshToken: false } }
const service = createClient(config.API_URL, config.SERVICE_ROLE_KEY, options)
const anon = createClient(config.API_URL, config.ANON_KEY, options)
const stamp = Date.now()
const address = (name: string) => `${name}-${stamp}@example.test`
const password = 'Local-worker-42!'
const ok = <T extends { data: unknown; error: unknown }>(result: T): T['data'] => { if (result.error) throw result.error; return result.data }
const captured: { html: string; recipient: string }[] = []
const actualFetch = globalThis.fetch
let providerStatus = 202
let staffToken = ''

function request(token = staffToken, requestId?: string) {
  return new Request('http://127.0.0.1/functions/v1/send-emails', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ request_id: requestId }) })
}

Deno.test('email worker: real approval → provider handoff → password activation, with safe retries', async () => {
  globalThis.fetch = async (input, init) => {
    const target = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
    if (target.hostname === 'api.sendgrid.com') {
      const body = JSON.parse(String(init?.body))
      captured.push({ html: body.content[0].value, recipient: body.personalizations[0].to[0].email })
      return new Response(null, { status: providerStatus })
    }
    if (target.hostname !== '127.0.0.1' || target.port !== '58321') throw new Error('Unexpected external network call')
    return actualFetch(input, init)
  }
  try {
    assert((await handleEmailRequest(request(''))).status === 401, 'Anonymous worker invocation must fail')
    const staff = ok(await service.auth.admin.createUser({ email: address('staff'), password, email_confirm: true })).user!
    ok(await service.from('platform_admins').insert({ profile_id: staff.id }))
    const staffClient = createClient(config.API_URL, config.ANON_KEY, options)
    staffToken = ok(await staffClient.auth.signInWithPassword({ email: address('staff'), password })).session!.access_token
    const outsider = ok(await service.auth.admin.createUser({ email: address('outsider'), password, email_confirm: true })).user!
    assert(outsider.id, 'Outsider created')
    const outsiderClient = createClient(config.API_URL, config.ANON_KEY, options)
    const outsiderToken = ok(await outsiderClient.auth.signInWithPassword({ email: address('outsider'), password })).session!.access_token
    assert((await handleEmailRequest(request(outsiderToken))).status === 403, 'Customer cannot invoke worker')
    ok(await anon.rpc('submit_access_request', { p_name: 'Worker Owner', p_email: address('owner'), p_phone: '+91 9999999999', p_company: 'Worker Studio', p_company_role: 'Founder', p_team_size: '2-5' }))
    const access = ok(await service.from('access_requests').select('id').eq('email', address('owner')).single())!
    ok(await staffClient.rpc('decide_access_request', { p_request_id: access.id, p_approve: true }))
    const outbox = () => service.from('email_outbox').select('*').eq('dedupe_key', `access-decision:${access.id}`).single()

    Deno.env.delete('SENDGRID_API_KEY')
    assert((await handleEmailRequest(request(staffToken, access.id))).status === 503, 'Missing sender config fails visibly')
    assert(ok(await outbox()).attempts === 0, 'Missing configuration must not consume delivery attempts')
    Deno.env.set('SENDGRID_API_KEY', 'local-fake-key')
    providerStatus = 503
    const failed = await (await handleEmailRequest(request(staffToken, access.id))).json()
    assert(failed.failed === 1 && failed.sent === 0, 'Provider failure is reported')
    const retryJob = ok(await outbox())
    assert(retryJob.status === 'queued' && retryJob.attempts === 1, 'Transient delivery is retryable')
    const savedLink = retryJob.payload.activation_url
    assert(typeof savedLink === 'string', 'Retry retains activation link')
    assert(!JSON.stringify(failed).includes('token_hash'), 'Response cannot expose token')
    assert(!retryJob.last_error.includes('token_hash'), 'Operator error cannot expose token')
    ok(await service.from('email_outbox').update({ locked_until: null }).eq('id', retryJob.id))
    providerStatus = 202
    const sent = await (await handleEmailRequest(request(staffToken, access.id))).json()
    assert(sent.sent === 1 && sent.failed === 0, 'Retry is sent')
    assert(captured.length === 2 && captured[0].html === captured[1].html, 'Retry uses the same welcome link')
    const delivered = ok(await outbox())
    assert(delivered.status === 'sent' && Object.keys(delivered.payload).length === 0, 'Sent job clears tokens')
    assert(captured[1].recipient === address('owner') && captured[1].html.includes('organisation owner'), 'Email addresses the approved owner')
    const activation = new URL(savedLink)
    const params = new URLSearchParams(activation.hash.slice(1))
    const owner = createClient(config.API_URL, config.ANON_KEY, options)
    ok(await owner.auth.verifyOtp({ type: 'invite', token_hash: params.get('token_hash')! }))
    ok(await owner.auth.updateUser({ password }))
    const workspaceId = ok(await owner.rpc('complete_approved_access'))
    assert(workspaceId, 'Emailed token activates owner organisation')
    ok(await staffClient.rpc('resend_access_welcome', { p_request_id: access.id }))
    assert((await (await handleEmailRequest(request(staffToken, access.id))).json()).sent === 1, 'Staff resend works for existing account')
    assert(captured.at(-1)!.html.includes('type=recovery'), 'Existing user receives recovery activation, not signup')
    const cron = await (await handleEmailRequest(request('local-worker-secret'))).json()
    assert(cron.sent >= 1, 'Private scheduled worker drains receipt queue')
    assert(captured.every((mail) => mail.recipient.endsWith('@example.test')), 'No real email recipients used')
  } finally {
    globalThis.fetch = actualFetch
  }
})
