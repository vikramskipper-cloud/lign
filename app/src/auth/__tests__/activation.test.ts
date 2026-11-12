import { describe, expect, it } from 'vitest'
import { readActivationLink } from '../activation'
import { activationUrl, invitationRoute, renderEmail, sendGridEmail, type EmailJob } from '../../../../supabase/functions/_shared/email'

const hash = 'a'.repeat(56) // GoTrue uses SHA-224 for email token hashes.
const job: EmailJob = { id: 'email-id', to_email: 'owner@example.test', template: 'access_request_approved', payload: { name: 'Ada', company: 'Example Studio' }, attempts: 1, lock_token: 'lease-id' }

describe('welcome email activation links', () => {
  it('opens the password form without leaking the token in the URL path or query', () => {
    const url = new URL(activationUrl('https://lign.example', hash, 'invite'))
    expect(url.pathname).toBe('/set-password')
    expect(url.search).toBe('')
    expect(readActivationLink(url.hash)).toEqual({ tokenHash: hash, type: 'invite', returnTo: '/dashboard' })
  })
  it('retains the invitation claim after password setup and sign-in', () => {
    const route = invitationRoute({ claim_route: '/org-invite', token: 'abc123' })
    const url = new URL(activationUrl('https://lign.example', hash, 'recovery', route))
    expect(readActivationLink(url.hash)?.returnTo).toBe('/org-invite/abc123')
  })
  it.each(['https://evil.example', '//evil.example', '/\\evil.example', '/sign-up', '/invite/a?next=https://evil.example'])('rejects an unsafe continuation: %s', (returnTo) => {
    const url = new URL(activationUrl('https://lign.example', hash, 'invite', returnTo))
    expect(readActivationLink(url.hash)?.returnTo).toBe('/dashboard')
  })
  it('rejects malformed links and public signup tokens', () => {
    expect(readActivationLink('#token_hash=invalid&type=invite')).toBeNull()
    expect(readActivationLink(`#token_hash=${hash}&type=signup`)).toBeNull()
    expect(() => invitationRoute({ claim_route: '//evil.example', token: 'abc' })).toThrow()
  })
})

describe('welcome email delivery', () => {
  it('describes owner access and includes password setup, escaping applicant content', () => {
    const email = renderEmail({ ...job, payload: { name: '<script>bad()</script>', company: 'A & B' } }, 'https://lign.example/set-password#token')
    expect(email.html).toContain('organisation owner')
    expect(email.html).toContain('Set your password')
    expect(email.html).toContain('A &amp; B')
    expect(email.html).not.toContain('<script>')
    expect(email.html).not.toContain('/sign-up')
  })
  it('refuses to send an approval without a password link', () => {
    expect(() => renderEmail(job)).toThrow('Password setup link required')
  })
  it('disables provider link tracking and keeps credentials out of the message body', async () => {
    let captured: RequestInit | undefined
    const fetcher: typeof fetch = async (_url, init) => { captured = init; return new Response(null, { status: 202 }) }
    await sendGridEmail('secret-key', 'welcome@lign.example', job.to_email, renderEmail(job, 'https://lign.example/set-password#token'), fetcher)
    expect(captured?.headers).toEqual({ Authorization: 'Bearer secret-key', 'Content-Type': 'application/json' })
    const body = JSON.parse(String(captured?.body))
    expect(body.tracking_settings.click_tracking.enable).toBe(false)
    expect(body.personalizations[0].to[0].email).toBe(job.to_email)
    expect(String(captured?.body)).not.toContain('secret-key')
  })
  it('reports a provider failure without disclosing its response body', async () => {
    const fetcher: typeof fetch = async () => new Response('sensitive provider details', { status: 403 })
    await expect(sendGridEmail('secret', 'welcome@lign.example', job.to_email, renderEmail(job, 'https://lign.example/set-password'), fetcher)).rejects.toThrow('Email provider rejected delivery (403)')
  })
})
