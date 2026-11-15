import { useQuery } from '@tanstack/react-query'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'

export interface AttentionItem {
  id: string; kind: 'brief' | 'proposal' | 'internal_signoff' | 'review' | 'approval' | 'library' | 'submission'
  title: string; to: string; responsible: string; canAct: boolean
  audience: 'team' | 'client' | 'reviewers'; since: string; dueAt: string | null
}
export interface ProjectSummary {
  projectId: string; workspaceId: string; internal: boolean; lead: string
  phase: string; briefReady: boolean; designReady: boolean; actions: AttentionItem[]
  shared: { id: string; name: string; revision: number; to: string; at: string; recipients: string | null; decisionStatus: string | null }[]
  activity: { id: string; eventType: string; subject: string | null; actor: string; at: string }[]
  accepted: { brief: boolean; proposal: boolean; briefRevision: { id:string; number:number } | null; proposalRevision: { id:string; number:number } | null }
}
export interface HubProject {
  id: string; name: string; code: string | null; status: string
  workspaceId: string; workspaceName: string; summary: ProjectSummary
}
export interface OverviewHub {
  organizationId: string; organizationName: string; projects: HubProject[]
  workspaces: { id: string; name: string; lead: string | null }[]; library: AttentionItem[]
}
export function useProjectSummary(projectId?: string) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['overview-project', user?.id, projectId], enabled: Boolean(user && projectId), refetchInterval: 15_000,
    queryFn: async (): Promise<ProjectSummary> => {
      const { data, error } = await supabase.rpc('get_project_overview', { p_project_id: projectId })
      if (error) throw error
      return data as ProjectSummary
    },
  })
}
export function useOverviewHub(orgId?: string, workspaceId?: string, personal = false) {
  const { user } = useSession()
  return useQuery({
    queryKey: ['overview-hub', user?.id, orgId, workspaceId, personal], enabled: Boolean(user && orgId), refetchInterval: 30_000,
    queryFn: async (): Promise<OverviewHub> => {
      const { data, error } = await supabase.rpc('get_overview_hub', {
        p_organization_id: orgId, p_workspace_id: workspaceId ?? null, p_personal: personal,
      })
      if (error) throw error
      return data as OverviewHub
    },
  })
}
export const attentionLabels: Record<AttentionItem['kind'], string> = {
  brief: 'Project brief', proposal: 'Design proposal', internal_signoff: 'Internal sign-off',
  review: 'Design review', approval: 'Design approval', library: 'Library review', submission: 'Consultant submission',
}
export function orderAttention<T extends AttentionItem>(items: T[]): T[] {
  return [...items].sort((a, b) => Number(b.canAct) - Number(a.canAct)
    || (a.dueAt ?? '9999').localeCompare(b.dueAt ?? '9999') || a.since.localeCompare(b.since) || a.id.localeCompare(b.id))
}
export function activityLabel(eventType: string) {
  const labels: Record<string, string> = {
    'design.internal_review_decided': 'Internal sign-off updated',
    'version.published': 'Design version published', 'approval.sent': 'Design sent for approval',
    'approval.approved': 'Design approved', 'proposal.accepted': 'Proposal accepted',
    'brief.agreed': 'Project brief agreed',
  }
  return labels[eventType] ?? eventType.replaceAll('.', ' · ').replaceAll('_', ' ')
}
