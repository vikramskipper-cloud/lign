export type ActivationLink = { tokenHash: string; type: 'invite' | 'recovery'; returnTo: string }

/** Tokens stay in the fragment, out of server logs and referrers. */
export function readActivationLink(hash: string): ActivationLink | null {
  const params = new URLSearchParams(hash.replace(/^#/, ''))
  const tokenHash = params.get('token_hash')
  const type = params.get('type')
  if (!tokenHash || !/^[a-f0-9]{56}$/i.test(tokenHash) || (type !== 'invite' && type !== 'recovery')) return null
  const candidate = params.get('returnTo') ?? ''
  // Only invitation claim routes are valid continuations.
  const returnTo = /^\/(?:org-invite|invite)\/[a-zA-Z0-9_-]+$/.test(candidate) ? candidate : '/dashboard'
  return { tokenHash, type, returnTo }
}
