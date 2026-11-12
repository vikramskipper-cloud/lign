import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

/**
 * APP 020 — beta access requests.
 *
 * Two audiences in one file, because they are two ends of one object:
 *
 *   useSubmitAccessRequest  the public form. Runs as `anon`, calls a definer
 *                           RPC, and can read nothing back.
 *   useAccessRequests       the admin triage list. Reads the table directly
 *   useDecideAccessRequest  under an RLS policy that admits organisation
 *                           owners and admins only.
 *
 * The asymmetry is deliberate. `access_requests` has no INSERT and no UPDATE
 * policy at all, so every write goes through a SECURITY DEFINER function that
 * decides what a stranger may set. A public INSERT policy would have let
 * anyone post a row with `status = 'approved'`.
 */

export const TEAM_SIZES = ['1', '2-5', '6-20', '21-50', '51-200', '200+'] as const
export type TeamSize = (typeof TEAM_SIZES)[number]

/** Mirrors the server regex in submit_access_request. */
export const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

export interface AccessRequestInput {
  name: string
  email: string
  phone: string
  companyRole: string
  teamSize: TeamSize
}

/**
 * Raised for a validation failure the server reported. The server is the
 * authority — the form checks the same rules first only so the common cases
 * never make a round trip.
 */
export class AccessRequestInvalid extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'AccessRequestInvalid'
  }
}

export function useSubmitAccessRequest() {
  return useMutation({
    mutationFn: async (input: AccessRequestInput): Promise<void> => {
      const { error } = await supabase.rpc('submit_access_request', {
        p_name: input.name.trim(),
        p_email: input.email.trim(),
        p_phone: input.phone.trim() || null,
        p_company_role: input.companyRole.trim(),
        p_team_size: input.teamSize,
      })
      if (!error) return

      // 22004 missing, 22001 too long, 22023 malformed. All three mean "fix
      // the form", so they carry the server's own message; anything else is
      // ours to apologise for and is handled by the caller.
      if (error.code === '22004' || error.code === '22001' || error.code === '22023') {
        throw new AccessRequestInvalid(
          error.message?.replace(/^submit_access_request:\s*/, '') ?? 'Check the details and try again.',
        )
      }
      throw error
    },
  })
}

/* ------------------------------------------------------------------ triage -- */

export type AccessRequestStatus = 'pending' | 'approved' | 'rejected'

export interface AccessRequest {
  id: string
  name: string
  email: string
  phone: string | null
  companyRole: string
  teamSize: string
  status: AccessRequestStatus
  note: string | null
  createdAt: string
  decidedAt: string | null
  decidedBy: { name: string } | null
}

/**
 * `status` of 'all' lists everything; otherwise one bucket. RLS does the
 * access control, so a non-admin gets an empty list rather than an error —
 * which is why the triage screen checks the caller's org role for itself
 * instead of inferring "no requests" from an empty read.
 */
export function useAccessRequests(status: AccessRequestStatus | 'all' = 'pending') {
  return useQuery({
    queryKey: qk.accessRequests(status),
    staleTime: 15_000,
    queryFn: async (): Promise<AccessRequest[]> => {
      let q = supabase
        .from('access_requests')
        .select(
          'id, name, email, phone, company_role, team_size, status, note, created_at, decided_at, ' +
            'decided_by:profiles!access_requests_decided_by_profile_id_fkey(display_name, email)',
        )
        .order('created_at', { ascending: false })
      if (status !== 'all') q = q.eq('status', status)

      const { data, error } = await q
      if (error) throw error

      type Raw = {
        id: string
        name: string
        email: string
        phone: string | null
        company_role: string
        team_size: string
        status: AccessRequestStatus
        note: string | null
        created_at: string
        decided_at: string | null
        decided_by: { display_name: string | null; email: string } | null
      }
      return ((data ?? []) as unknown as Raw[]).map((r) => ({
        id: r.id,
        name: r.name,
        email: r.email.toLowerCase(),
        phone: r.phone,
        companyRole: r.company_role,
        teamSize: r.team_size,
        status: r.status,
        note: r.note,
        createdAt: r.created_at,
        decidedAt: r.decided_at,
        decidedBy: r.decided_by
          ? { name: r.decided_by.display_name ?? r.decided_by.email }
          : null,
      }))
    },
  })
}

/** How many are waiting — for the nav badge and the screen header. */
export function usePendingAccessRequestCount() {
  const pending = useAccessRequests('pending')
  return pending.data?.length ?? 0
}

export function useDecideAccessRequest() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { id: string; approve: boolean; note?: string }) => {
      const { error } = await supabase.rpc('decide_access_request', {
        p_request_id: input.id,
        p_approve: input.approve,
        p_note: input.note?.trim() || null,
      })
      if (error) throw error
    },
    // refetchType 'all': the lists for the other buckets are usually inactive,
    // and a plain invalidate leaves an inactive query merely stale — so
    // switching tabs would show the row in its old bucket.
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: ['access-requests'], refetchType: 'all' }),
        qc.invalidateQueries({ queryKey: ['email-outbox'], refetchType: 'all' }),
      ])
    },
  })
}

/* ------------------------------------------------------------------ outbox -- */

export interface QueuedEmail {
  id: string
  toEmail: string
  template: string
  status: 'queued' | 'sent' | 'failed'
  attempts: number
  lastError: string | null
  createdAt: string
  sentAt: string | null
}

/**
 * The to-send list. Nothing drains it yet — SendGrid is not wired — so this
 * exists so an admin can see what *would* have gone out and to whom, rather
 * than the queue being invisible until a sender appears.
 */
export function useEmailOutbox(status: 'queued' | 'sent' | 'failed' | 'all' = 'queued') {
  return useQuery({
    queryKey: qk.emailOutbox(status),
    staleTime: 15_000,
    queryFn: async (): Promise<QueuedEmail[]> => {
      let q = supabase
        .from('email_outbox')
        .select('id, to_email, template, status, attempts, last_error, created_at, sent_at')
        .order('created_at', { ascending: false })
        .limit(200)
      if (status !== 'all') q = q.eq('status', status)

      const { data, error } = await q
      if (error) throw error
      return ((data ?? []) as {
        id: string
        to_email: string
        template: string
        status: 'queued' | 'sent' | 'failed'
        attempts: number
        last_error: string | null
        created_at: string
        sent_at: string | null
      }[]).map((r) => ({
        id: r.id,
        toEmail: r.to_email.toLowerCase(),
        template: r.template,
        status: r.status,
        attempts: r.attempts,
        lastError: r.last_error,
        createdAt: r.created_at,
        sentAt: r.sent_at,
      }))
    },
  })
}
