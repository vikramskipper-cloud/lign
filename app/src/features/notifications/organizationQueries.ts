import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import type { InboxResponse } from './types'

export function useOrganizationBadge(org?: string) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['notification', 'organization-badge', org, user?.id], enabled: Boolean(org && user),
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('list_organization_notifications', { p_organization_id: org, p_limit: 1 })
      if (error) throw error
      return (data as InboxResponse).facets.unread_count
    },
  })
}
