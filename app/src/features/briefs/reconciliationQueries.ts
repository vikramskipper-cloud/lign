import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import type { BriefItem } from './model'
export interface RequirementChange {
  itemId: string
  kind: 'added' | 'changed' | 'unchanged' | 'removed'
  state: 'pending' | 'applied' | 'matched'
  outcome: string | null
  note: string
  appliedAt: string | null
  matchedItemId: string | null
  matchedFrom?: string | null
  previousItem: BriefItem | null
  proposedItem: BriefItem | null
  responsibilityValid: boolean
  manualEdits: boolean
  impact: { assets: number; assessments: number; proposals: number }
  token: string
  previous: {
    id: string
    code: string
    status: string
    content: {
      title: string
      description: string
      priority: string
      owner_profile_id: string | null
    }
  } | null
  next: RequirementChange['previous']
}
export interface RequirementHandoff {
  canManage: boolean
  canRetire: boolean
  current: boolean
  prepared: boolean
  pending: number
  rows: RequirementChange[]
}
export function useBriefRequirementChanges(
  projectId: string,
  revisionId: string,
  enabled = true,
) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['brief-reconciliation', user?.id, projectId, revisionId],
    enabled: Boolean(user && revisionId && enabled),
    refetchInterval: 30000,
    staleTime: 0,
    retry: 1,
    queryFn: async () => {
      const r = await supabase.rpc('get_brief_requirement_changes', {
        p_project_id: projectId,
        p_revision_id: revisionId,
      })
      if (r.error) throw r.error
      return r.data as RequirementHandoff
    },
  })
}
