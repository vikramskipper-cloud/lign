import { supabase } from '@/lib/supabase'

/**
 * APP 023. Hands an invitation token back to the server so the invitation
 * email is queued for delivery.
 *
 * Called AFTER the inviting RPC has returned — i.e. after its transaction has
 * committed — which is what the APP 014 brief asked for: "send invite emails
 * only after the transaction commits." The server finds the invitation by
 * sha256 of the token, so possession is the credential, and it deduplicates
 * per invitation, so calling twice sends one email.
 *
 * NEVER REJECTS. A queueing failure must not fail the invitation that already
 * succeeded: the invite exists, the link works, and copy-a-link delivery is
 * still available. Swallowing it keeps a mail problem from being reported to
 * the user as "the invite failed" when it did not.
 *
 * The cost of that choice is that a failure is silent to the user. It is NOT
 * silent to an operator: the row is simply absent from the outbox, which the
 * access-requests screen surfaces as a queue count, and nothing has been sent
 * yet in any case — no mail provider is wired.
 */
export async function queueInvitationEmail(token: string | null | undefined): Promise<boolean> {
  if (!token) return false
  const { error } = await supabase.rpc('queue_invitation_email', { p_token: token })
  if (error) {
    // Deliberately console, not toast. See above.
    console.warn('[lign] could not queue the invitation email', error.code ?? error.message)
    return false
  }
  return true
}

/** Queues several, independently: one failure must not skip the rest. */
export async function queueInvitationEmails(
  tokens: (string | null | undefined)[],
): Promise<number> {
  const results = await Promise.all(tokens.map((t) => queueInvitationEmail(t)))
  return results.filter(Boolean).length
}
