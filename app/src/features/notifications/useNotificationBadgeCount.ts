/**
 * APP 010 §14.1 / §18.2: bell-icon unread count hook.
 * Polls every 60s (per §25.4) via React Query refetchInterval.
 * Re-exported convenience over the base queries hook.
 */

export { useNotificationBadgeCount } from './queries'
