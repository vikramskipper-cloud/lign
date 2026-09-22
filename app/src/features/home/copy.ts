/**
 * User-facing nouns for Home, in one place.
 *
 * Per open decision 2: "Release" stays in code and UI for now, but may become
 * "Package" or "Issued set" for non-software customers. Changing that term
 * should be an edit here, not a grep across components.
 */
export const COPY = {
  release: 'release',
  releasePlural: 'releases',
  Release: 'Release',
  approval: 'approval',
  approvalPlural: 'approvals',
  Approval: 'Approval',
  review: 'review',
  reviewPlural: 'reviews',
  version: 'version',
} as const

/**
 * Days pending before an item reads as overdue rather than merely open.
 * Named so the threshold is tuneable in one place, per the brief.
 */
export const STALE_AFTER_DAYS = 3

/** Needs-you rows shown before collapsing into "View all". */
export const NEEDS_YOU_CAP = 8
export const WAITING_CAP = 5
export const PROJECTS_CAP = 5
export const ACTIVITY_CAP = 5
export const PINNED_CAP = 5

/**
 * Multi-approver rule (open decision 1). Default: a request needs EVERY
 * required approver, not just one.
 *
 * Deliberately a single function so switching to any-one is a one-line change.
 * Note the database already models this on approval_requests.policy
 * ('any' | 'all') and quorum_min — this mirrors it for display only and must
 * never be treated as the authority. The RPC decides the real outcome.
 */
export function isSatisfied(opts: {
  policy: 'any' | 'all' | string
  approvals: number
  requiredApprovers: number
  quorumMin: number | null
}): boolean {
  if (opts.policy === 'any') return opts.approvals >= 1
  if (opts.quorumMin != null) return opts.approvals >= opts.quorumMin
  return opts.approvals >= opts.requiredApprovers
}
