/**
 * APP 011 §12 — channel names. Every realtime channel name in the app comes
 * from here, including the two APP 010 reserved before this module existed
 * (APP 010 §25.3 placed them in features/notifications/realtime.ts, a file that
 * was never created; per the APP 011 Backend Delta §5 they live here instead).
 */

/** Wave 1A: one channel per active workspace, carrying all table bindings. */
export const wsChannel = (wsId: string) => `lign:ws:${wsId}`

/** Wave 2 (not subscribed in wave 1). */
export const versionPresenceChannel = (versionId: string) =>
  `lign:presence:version:${versionId}`

/** APP 010 §25.3 reserved. Subscribed in wave 1B once `notifications` joins the publication. */
export const notificationsProfileChannel = (profileId: string) =>
  `notifications:profile:${profileId}`
export const notificationsWorkspaceChannel = (wsId: string) =>
  `notifications:workspace:${wsId}`

/**
 * The frozen REALTIME 002 publication scope. Exactly these 8 tables are live;
 * adding to this array without a REALTIME re-freeze produces bindings that
 * silently never fire, because the table is not in the publication.
 */
export const REALTIME_TABLES = [
  'comments',
  'annotations',
  'asset_versions',
  'design_assets',
  'reviews',
  'review_participants',
  'approval_requests',
  'approval_responses',
] as const

/**
 * REALTIME 003 (APP 011 wave 1B). Deliberately NOT in REALTIME_TABLES: every
 * table there is narrowed by `workspace_id`, but a notification is scoped to a
 * recipient. It gets its own binding with `recipient_profile_id=eq.<id>`,
 * which is also the tighter filter — a user receives only their own rows.
 */
export const NOTIFICATION_TABLE = 'notifications' as const

export type RealtimeTable =
  | (typeof REALTIME_TABLES)[number]
  | typeof NOTIFICATION_TABLE

/**
 * APP 011 F-4: no DELETE policy exists on any of the 8 tables, so authenticated
 * clients cannot hard-delete them (the domain soft-deletes via `status`).
 * Subscribing to DELETE would also be useless: all 8 have
 * `replica identity = default`, so a DELETE payload carries only the primary
 * key and could never match the `workspace_id` filter.
 */
export const REALTIME_EVENTS = ['INSERT', 'UPDATE'] as const
