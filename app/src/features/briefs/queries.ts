import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'
import type { BriefDocument } from './model'

export interface BriefFile {
  id: string
  name: string
  storage_path: string
  size_bytes: number
  created_at: string
}
export interface BriefRevision {
  id: string
  number: number
  document: BriefDocument
  attachments: BriefFile[]
  created_at: string
  requested_by: string
  respondent_participant_id: string
  decision: {
    decision: 'agreed' | 'changes_requested'
    comment: string
    actorName: string
    created_at: string
  } | null
  generatedCount: number
}
export interface ProjectBriefData {
  organizationDisciplines?: string[]
  brief: {
    id: string
    project_id: string
    status: 'draft' | 'submitted' | 'awaiting_agreement' | 'agreed'
    document: BriefDocument
    edit_version: number
    revision_number: number
    current_revision_id: string | null
    respondent_participant_id: string | null
    updated_at?: string
    created_at?: string
  } | null
  canManage: boolean
  canEdit: boolean
  canRespond: boolean
  canComment: boolean
  canGenerate: boolean
  approvers: { id: string; name: string; pending: boolean }[]
  owners: { id: string; name: string }[]
  files: BriefFile[]
  revisions: BriefRevision[]
  notes: { id: string; authorName: string; body: string; created_at: string }[]
}
export function useProjectBrief(projectId?: string) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['project-brief', user?.id, projectId],
    enabled: Boolean(user && projectId),
    refetchInterval: 30_000,
    retry: (count, error) =>
      (error as { code?: string }).code !== '42501' && count < 2,
    queryFn: async (): Promise<ProjectBriefData> => {
      const { data, error } = await supabase.rpc('get_project_brief', {
        p_project_id: projectId,
      })
      if (error) throw error
      return data as ProjectBriefData
    },
  })
}

/** Keep the next-step action aligned with the server's proposal preparation permissions. */
export function useBriefProposalAccess(projectId: string, enabled: boolean) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['brief-proposal-access', user?.id, projectId],
    refetchInterval: 30_000,
    enabled: Boolean(user && projectId && enabled),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('lign_prepare_proposal', {
        p_project_id: projectId,
      })
      if (error) throw error
      return data === true
    },
    retry: 1,
  })
}

export interface BriefReadinessContext {
  version: number
  respondentId: string | null
  people: { id: string; name: string; role: 'lead' | 'contributor' }[]
  defaultOwner: {
    id: string
    name: string
    role: 'lead' | 'contributor'
  } | null
  approver: {
    id: string
    name: string
    pending: boolean
    available: boolean
    isRequester: boolean
  } | null
  selectedReferenceCount: number
  referenceError: string | null
  canRequest: boolean
  canSubmit: boolean
}
export function useBriefReadiness(
  projectId: string,
  respondent: string,
  version: number,
  enabled: boolean,
) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['brief-readiness', user?.id, projectId, respondent, version],
    staleTime: 0,
    enabled: Boolean(user && projectId && enabled),
    refetchInterval: 30000,
    retry: 1,
    queryFn: async (): Promise<BriefReadinessContext> => {
      const { data, error } = await supabase.rpc(
        'get_project_brief_readiness',
        {
          p_project_id: projectId,
          p_respondent_participant_id: respondent || null,
        },
      )
      if (error) throw error
      return data as BriefReadinessContext
    },
  })
}
