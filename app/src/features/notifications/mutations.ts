import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import {
  invalidateNotifications,
  invalidateNotificationBadge,
} from '@/features/shared/invalidate'

/**
 * APP 010 mutations. Each wraps a SECURITY DEFINER write RPC that enforces
 * recipient_profile_id = auth.uid() in-body and gates on notification.manage.
 */

export function useMarkNotificationRead(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string): Promise<boolean> => {
      const { data, error } = await supabase.rpc('mark_notification_read', {
        p_notification_id: id,
      })
      if (error) throw error
      return Boolean(data)
    },
    onSuccess: () => {
      invalidateNotifications(qc, wsId)
      invalidateNotificationBadge(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useMarkNotificationUnread(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string): Promise<boolean> => {
      const { data, error } = await supabase.rpc('mark_notification_unread', {
        p_notification_id: id,
      })
      if (error) throw error
      return Boolean(data)
    },
    onSuccess: () => {
      invalidateNotifications(qc, wsId)
      invalidateNotificationBadge(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useMarkAllNotificationsRead(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (category: string | null = null): Promise<number> => {
      const { data, error } = await supabase.rpc('mark_all_notifications_read', {
        p_ws_id: wsId,
        p_category: category,
      })
      if (error) throw error
      return Number(data ?? 0)
    },
    onSuccess: (count) => {
      if (count > 0) toast.success(`Marked ${count} as read`)
      invalidateNotifications(qc, wsId)
      invalidateNotificationBadge(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useDismissNotification(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string): Promise<boolean> => {
      const { data, error } = await supabase.rpc('dismiss_notification', {
        p_notification_id: id,
      })
      if (error) throw error
      return Boolean(data)
    },
    onSuccess: () => {
      invalidateNotifications(qc, wsId)
      invalidateNotificationBadge(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useArchiveNotification(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string): Promise<boolean> => {
      const { data, error } = await supabase.rpc('archive_notification', {
        p_notification_id: id,
      })
      if (error) throw error
      return Boolean(data)
    },
    onSuccess: () => {
      invalidateNotifications(qc, wsId)
      invalidateNotificationBadge(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}
