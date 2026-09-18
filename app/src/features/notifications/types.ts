/**
 * APP 010 — Notification domain types.
 * Mirrors public.notifications columns + payload shape (§4.1, §10.4).
 */

export type NotificationCategory =
  | 'assigned_to_me'
  | 'mentions'
  | 'project_activity'
  | 'governance_state_change'
  | 'deadlines'
  | 'system'

export type NotificationPriority =
  | 'critical'
  | 'high'
  | 'medium'
  | 'low'
  | 'informational'

export type InboxTab =
  | 'all'
  | 'unread'
  | 'mentions'
  | 'assigned'
  | 'governance'
  | 'archived'

export type SourceModule =
  | 'review'
  | 'approval'
  | 'requirement'
  | 'release'
  | 'comment'
  | 'change'
  | 'annotation'
  | 'project'
  | 'workspace'
  | 'stakeholder'
  | 'invitation'

export interface NotificationDeepLink {
  kind: string
  id: string | null
  workspace_id: string
  project_id: string | null
  extra?: Record<string, unknown>
}

export interface NotificationPayload {
  source_event_type: string
  actor_profile_id: string | null
  /** Canonical position for actor display name per F-5. */
  actor_display_name: string
  subject_kind: string | null
  subject_id: string | null
  subject_label: string | null
  occurred_at: string
  deep_link: NotificationDeepLink
  preview_snippet: string
  // Optional (email-ready / push-ready) fields per §10.4
  email_subject_line?: string
  email_body_snippet?: string
  email_cta_url?: string
  email_cta_label?: string
  push_title?: string
  push_body?: string
  push_data?: Record<string, unknown>
}

export interface Notification {
  id: string
  workspace_id: string
  project_id: string | null
  recipient_profile_id: string
  source_event_id: string
  event_type: string
  notification_type: string
  category: NotificationCategory
  priority: NotificationPriority
  channels_attempted: string[]
  delivery_state: 'pending' | 'delivered' | 'failed' | 'suppressed'
  subject_kind: string
  subject_id: string | null
  subject_label: string | null
  actor_profile_id: string | null
  payload: NotificationPayload
  read_at: string | null
  dismissed_at: string | null
  archived_at: string | null
  created_at: string
  updated_at: string
}

export interface InboxFilters {
  category?: NotificationCategory[]
  priority?: NotificationPriority[]
  source?: SourceModule[]
  dateFrom?: string | null
  dateTo?: string | null
  cursor?: { created_at: string; id: string } | null
  limit?: number
}

export interface InboxFacets {
  total_count: number
  unread_count: number
  by_category: Partial<Record<NotificationCategory, number>>
  by_priority: Partial<Record<NotificationPriority, number>>
}

export interface InboxResponse {
  rows: Notification[]
  next_cursor: { created_at: string; id: string } | null
  has_more: boolean
  facets: InboxFacets
}

export interface BadgeCount {
  total_unread: number
  by_category: Partial<Record<NotificationCategory, number>>
  has_critical: boolean
}

export interface NotificationCenterResponse {
  rows: Notification[]
  has_more: boolean
  total_unread: number
}
