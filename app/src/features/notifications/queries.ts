import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import type {
  BadgeCount,
  InboxFilters,
  InboxResponse,
  InboxTab,
  Notification,
  NotificationCenterResponse,
} from './types'

/**
 * APP 010 — Notification read hooks. Every hook wraps a SECURITY DEFINER RPC
 * that gates on notification.view and enforces recipient_profile_id = auth.uid().
 */

const EMPTY_FILTERS: Record<string, unknown> = {}

export function useNotificationsInbox(
  wsId: string | undefined,
  tab: InboxTab,
  filters: InboxFilters,
) {
  return useQuery({
    queryKey: wsId
      ? qk.notificationsInbox(
          wsId,
          tab,
          {
            category: filters.category ?? null,
            priority: filters.priority ?? null,
            source: filters.source ?? null,
            dateFrom: filters.dateFrom ?? null,
            dateTo: filters.dateTo ?? null,
            limit: filters.limit ?? 50,
          },
          filters.cursor ?? null,
        )
      : ['notification', 'inbox', 'none'],
    enabled: Boolean(wsId),
    staleTime: 60_000,
    queryFn: async (): Promise<InboxResponse> => {
      const { data, error } = await supabase.rpc('list_notifications_inbox', {
        p_ws_id: wsId as string,
        p_tab: tab,
        p_category_filter: filters.category ?? null,
        p_priority_filter: filters.priority ?? null,
        p_source_filter: filters.source ?? null,
        p_date_from: filters.dateFrom ?? null,
        p_date_to: filters.dateTo ?? null,
        p_cursor_created_at: filters.cursor?.created_at ?? null,
        p_cursor_id: filters.cursor?.id ?? null,
        p_limit: filters.limit ?? 50,
      })
      if (error) throw error
      return (data as InboxResponse) ?? { rows: [], next_cursor: null, has_more: false, facets: { total_count: 0, unread_count: 0, by_category: {}, by_priority: {} } }
    },
  })
}

export function useNotification(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.notification(id) : ['notification', 'none'],
    enabled: Boolean(id),
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<Notification | null> => {
      const { data, error } = await supabase.rpc('get_notification', {
        p_notification_id: id as string,
      })
      if (error) throw error
      return (data as Notification | null) ?? null
    },
  })
}

export function useNotificationBadgeCount(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId ? qk.notificationBadgeCount(wsId) : ['notification', 'badge', 'none'],
    enabled: Boolean(wsId),
    staleTime: 30_000,
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<BadgeCount> => {
      const { data, error } = await supabase.rpc('get_notification_badge_count', {
        p_ws_id: wsId as string,
      })
      if (error) throw error
      return (data as BadgeCount) ?? { total_unread: 0, by_category: {}, has_critical: false }
    },
  })
}

export function useNotificationCenter(wsId: string | undefined, limit = 15) {
  return useQuery({
    queryKey: wsId ? qk.notificationCenter(wsId) : ['notification', 'center', 'none'],
    enabled: Boolean(wsId),
    staleTime: 30_000,
    refetchInterval: 60_000,
    queryFn: async (): Promise<NotificationCenterResponse> => {
      const { data, error } = await supabase.rpc('get_notification_center', {
        p_ws_id: wsId as string,
        p_limit: limit,
      })
      if (error) throw error
      return (
        (data as NotificationCenterResponse) ?? { rows: [], has_more: false, total_unread: 0 }
      )
    },
  })
}

export function useNotificationsBySource(
  subjectKind: string | null,
  subjectId: string | null,
  limit = 50,
) {
  return useQuery({
    queryKey:
      subjectKind && subjectId
        ? qk.notificationsBySource(subjectKind, subjectId)
        : ['notification', 'subject', 'none'],
    enabled: Boolean(subjectKind && subjectId),
    staleTime: 60_000,
    queryFn: async (): Promise<Notification[]> => {
      const { data, error } = await supabase.rpc('list_notifications_by_source', {
        p_source_kind: subjectKind as string,
        p_source_id: subjectId as string,
        p_limit: limit,
      })
      if (error) throw error
      return (data as Notification[] | null) ?? []
    },
  })
}

// Keep import surface warning-free for consumers that only want types.
export type { InboxFilters, InboxResponse, InboxTab, Notification }
export { EMPTY_FILTERS }
