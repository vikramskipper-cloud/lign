/**
 * Route module for /access-requests, so the triage screen is code-split.
 *
 * It is reachable only by organisation owners and admins, and most sessions
 * never open it — keeping it in the initial bundle spent everyone's first
 * paint on a screen almost nobody loads. The initial budget had 2.6 KB of
 * headroom before this was split out.
 */
export { AccessRequestsScreen as Component, AccessRequestsHandle as handle } from './AccessRequestsScreen'
