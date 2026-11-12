import { createClient } from 'npm:@supabase/supabase-js@2.109.0'
import { activationUrl, invitationRoute, renderEmail, sendGridEmail, type EmailJob } from '../_shared/email.ts'

const env = (name: string) => {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`Missing server configuration: ${name}`)
  return value
}

export async function handleEmailRequest(request: Request): Promise<Response> {
  // CORS grants no authority. Every non-cron request must have a valid staff JWT.
  const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' }
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers })
  if (request.method === 'OPTIONS') return reply({})
  if (request.method !== 'POST') return reply({ error: 'POST required' }, 405)

  try {
    const service = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } })
    const bearer = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ?? ''
    const workerToken = Deno.env.get('EMAIL_WORKER_TOKEN')
    const isWorker = Boolean(workerToken && bearer === workerToken)
    let outboxId: string | null = null
    if (!isWorker) {
      const { data: identity, error } = await service.auth.getUser(bearer)
      if (error || !identity.user) return reply({ error: 'Authentication required' }, 401)
      const { data: admin } = await service.from('platform_admins').select('profile_id').eq('profile_id', identity.user.id).maybeSingle()
      if (!admin) return reply({ error: 'LIGN staff only' }, 403)
      const body = await request.json()
      if (typeof body.request_id !== 'string') return reply({ error: 'request_id required' }, 400)
      const { data: queued, error: queueError } = await service.from('email_outbox').select('id')
        .eq('dedupe_key', `access-decision:${body.request_id}`).eq('status', 'queued').maybeSingle()
      if (queueError) throw queueError
      if (!queued) return reply({ sent: 0, failed: 0 })
      outboxId = queued.id
    }

    // Validate before taking leases; missing credentials must leave jobs untouched.
    const apiKey = env('SENDGRID_API_KEY')
    const from = env('EMAIL_FROM')
    const appUrl = env('APP_URL')
    if (!/^https:\/\//.test(appUrl) && !/^http:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/.test(appUrl)) throw new Error('APP_URL must use HTTPS')
    const { data: jobs, error } = await service.rpc('claim_email_batch', { p_outbox_id: outboxId })
    if (error) throw error
    let sent = 0
    let failed = 0
    for (const job of (jobs ?? []) as EmailJob[]) {
      const update = async (values: Record<string, unknown>) => {
        const { data, error } = await service.from('email_outbox').update(values)
          .eq('id', job.id).eq('lock_token', job.lock_token).select('id').single()
        if (error || !data) throw new Error('Could not update delivery lease')
      }
      try {
        const approved = job.template === 'access_request_approved'
        const invitation = ['org_invitation', 'workspace_member_invitation', 'stakeholder_invitation'].includes(job.template)
        let returnTo = '/dashboard'
        if (approved) {
          // Re-check approval at send time. Old queued records have no request_id.
          let query = service.from('access_requests').select('id, name, company').eq('email', job.to_email).eq('status', 'approved')
          if (typeof job.payload.request_id === 'string') query = query.eq('id', job.payload.request_id)
          const { data: access, error } = await query.order('decided_at', { ascending: false }).limit(1).single()
          if (error || !access?.company) throw new Error('Approved request needs a company name')
          job.payload = { ...job.payload, name: access.name, company: access.company, request_id: access.id }
        }
        if (invitation) {
          returnTo = invitationRoute(job.payload)
          job.payload.claim_url = new URL(returnTo, appUrl).toString()
          // Do not create an auth account for a revoked, claimed, or expired invite.
          const table = job.template === 'org_invitation' ? 'organization_invitations' : 'invitations'
          const { data: invite, error } = await service.from(table).select('status, expires_at, email').eq('id', job.payload.invitation_id).single()
          if (error || !invite || invite.status !== 'sent' || new Date(invite.expires_at).getTime() <= Date.now() || invite.email.toLowerCase() !== job.to_email.toLowerCase()) throw new Error('Invitation is no longer valid')
        }
        let passwordUrl: string | undefined
        if (approved || invitation) {
          passwordUrl = typeof job.payload.activation_url === 'string' ? job.payload.activation_url : undefined
          if (!passwordUrl) {
            const { data: profile, error: lookupError } = await service.from('profiles').select('id').eq('email', job.to_email).maybeSingle()
            if (lookupError) throw lookupError
            let type: 'invite' | 'recovery' = profile ? 'recovery' : 'invite'
            let result = await service.auth.admin.generateLink(type === 'invite'
              ? { type: 'invite', email: job.to_email, options: { data: { display_name: String(job.payload.name || job.to_email) } } }
              : { type: 'recovery', email: job.to_email })
            if (['email_exists', 'email_exists_unconfirmed'].includes(result.error?.code ?? '') && type === 'invite') {
              type = 'recovery'
              result = await service.auth.admin.generateLink({ type, email: job.to_email })
            }
            if (result.error || !result.data.properties?.hashed_token) throw new Error('Could not prepare password setup link')
            passwordUrl = activationUrl(appUrl, result.data.properties.hashed_token, type, returnTo)
            job.payload.activation_url = passwordUrl
            // Persist before send: a retry reuses the link rather than invalidating
            // one the provider might already have delivered before a timeout.
            await update({ payload: job.payload })
          }
        }
        await sendGridEmail(apiKey, from, job.to_email, renderEmail(job, passwordUrl))
        await update({ status: 'sent', sent_at: new Date().toISOString(), payload: {}, last_error: null, locked_until: null, lock_token: null })
        sent++
      } catch {
        failed++
        // Keep secrets and password links out of errors visible to operators.
        await update({ status: job.attempts >= 5 ? 'failed' : 'queued', last_error: 'Delivery failed. Check sender configuration or resend the welcome email.', locked_until: new Date(Date.now() + 60_000).toISOString(), lock_token: null })
      }
    }
    return reply({ sent, failed })
  } catch {
    return reply({ error: 'Email delivery unavailable. Check server configuration.' }, 503)
  }
}
