export interface EmailJob {
  id: string
  to_email: string
  template: string
  payload: Record<string, unknown>
  attempts: number
  lock_token: string
}

export function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]!)
}

export function activationUrl(appUrl: string, tokenHash: string, type: 'invite' | 'recovery', returnTo = '/dashboard'): string {
  const url = new URL('/set-password', appUrl)
  url.hash = new URLSearchParams({ token_hash: tokenHash, type, returnTo }).toString()
  return url.toString()
}

export function invitationRoute(payload: Record<string, unknown>): string {
  const route = payload.claim_route
  const token = payload.token
  if ((route !== '/invite' && route !== '/org-invite') || typeof token !== 'string' || !/^[a-zA-Z0-9_-]+$/.test(token)) {
    throw new Error('Invalid invitation link')
  }
  return `${route}/${token}`
}

export function renderEmail(job: EmailJob, passwordUrl?: string): { subject: string; html: string } {
  const name = escapeHtml(job.payload.name || 'there')
  if (job.template === 'access_request_received') {
    return { subject: 'We received your LIGN access request', html: `<p>Hi ${name},</p><p>We received your request. LIGN will review it and email you a welcome link if approved.</p>` }
  }
  if (job.template === 'access_request_declined') {
    return { subject: 'Your LIGN access request', html: `<p>Hi ${name},</p><p>Thank you for your interest. We cannot approve your access request at this time.</p>` }
  }
  if (!passwordUrl) throw new Error('Password setup link required')
  const button = `<p><a href="${escapeHtml(passwordUrl)}">Set your password</a></p><p>This secure link expires in one hour and can only be used once. If it expires, request a new password link from the sign-in page.</p>`
  if (job.template === 'access_request_approved') {
    return {
      subject: 'Welcome to LIGN — set your password',
      html: `<p>Hi ${name},</p><p>Your access request has been approved. Welcome to LIGN!</p><p>Set your password to activate <strong>${escapeHtml(job.payload.company)}</strong>. You will be its organisation owner. Then sign in with ${escapeHtml(job.to_email)} and your new password.</p>${button}`,
    }
  }
  if (['org_invitation', 'workspace_member_invitation', 'stakeholder_invitation'].includes(job.template)) {
    return { subject: `You are invited to ${String(job.payload.context_name || 'LIGN')}`, html: `<p>You have been invited to ${escapeHtml(job.payload.context_name || 'LIGN')}.</p><p>Set a password, then sign in to accept your invitation.</p>${button}<p>Already have a password? <a href="${escapeHtml(job.payload.claim_url)}">Sign in and accept the invitation</a>.</p>` }
  }
  throw new Error('Unknown email template')
}

/** Separately injectable for delivery tests. Provider errors must never expose links or keys. */
export async function sendGridEmail(apiKey: string, from: string, to: string, message: { subject: string; html: string }, fetcher: typeof fetch = fetch): Promise<void> {
  const response = await fetcher('https://api.sendgrid.com/v3/mail/send', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: from, name: 'LIGN' },
      subject: message.subject,
      content: [{ type: 'text/html', value: message.html }],
      tracking_settings: { click_tracking: { enable: false, enable_text: false }, open_tracking: { enable: false } },
    }),
    signal: AbortSignal.timeout(15_000),
  })
  if (!response.ok) throw new Error(`Email provider rejected delivery (${response.status})`)
}
