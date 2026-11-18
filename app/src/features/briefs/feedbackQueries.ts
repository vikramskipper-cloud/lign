import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
export interface BriefFeedbackItem {
  id: string
  sourceRevisionId: string
  sourceNumber: number
  targetKind: 'overall' | 'field' | 'item' | 'reference'
  targetId: string | null
  body: string
  fromDecision: boolean
  creatorName: string
  createdAt: string
  status: 'open' | 'addressed' | 'verified'
  version: number
  response: string
  addressedBy: string | null
  addressedAt: string | null
  responseRevisionId: string | null
  responseNumber: number | null
  responseEditVersion: number | null
  verifiedBy: string | null
  verifiedAt: string | null
  verifiedNumber: number | null
  stale: boolean
  canVerify: boolean
  canReopen: boolean
  events: {
    action: string
    note: string
    at: string
    actorName: string
    revisionNumber: number | null
  }[]
}
export interface BriefFeedbackData {
  canAddress: boolean
  canCreateFor: { id: string; number: number }[]
  rows: BriefFeedbackItem[]
}
export function useBriefFeedback(projectId: string, enabled = true) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['brief-feedback', user?.id, projectId],
    enabled: Boolean(user && enabled),
    refetchInterval: 30000,
    staleTime: 0,
    retry: 1,
    queryFn: async () => {
      const r = await supabase.rpc('get_brief_feedback', {
        p_project_id: projectId,
      })
      if (r.error) throw r.error
      return r.data as BriefFeedbackData
    },
  })
}
