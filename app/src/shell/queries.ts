import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export interface WorkspaceRow {
  id: string
  name: string
  slug: string
  status: string
}

export interface ProjectRow {
  id: string
  workspace_id: string
  name: string
  slug: string
  status: string
  description: string | null
  code: string | null
  archived_at: string | null
  created_at: string
  updated_at: string
}

const PROJECT_COLS =
  'id, workspace_id, name, slug, status, description, code, archived_at, created_at, updated_at'

/** All workspaces the caller can see (via workspace_members RLS). */
export function useWorkspaces() {
  return useQuery({
    queryKey: qk.workspaces(),
    queryFn: async (): Promise<WorkspaceRow[]> => {
      const { data, error } = await supabase
        .from('workspaces')
        .select('id, name, slug, status')
        .order('name')
      if (error) throw error
      return data ?? []
    },
  })
}

export function useWorkspace(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.workspace(id) : ['workspace', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<WorkspaceRow | null> => {
      const { data, error } = await supabase
        .from('workspaces')
        .select('id, name, slug, status')
        .eq('id', id as string)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
}

/** Projects inside a workspace, visible to the caller. Ordered by updated_at desc. */
export function useProjects(wsId: string | undefined) {
  return useQuery({
    queryKey: wsId ? qk.projects(wsId) : ['workspace', 'none', 'projects'],
    enabled: Boolean(wsId),
    queryFn: async (): Promise<ProjectRow[]> => {
      const { data, error } = await supabase
        .from('projects')
        .select(PROJECT_COLS)
        .eq('workspace_id', wsId as string)
        .is('archived_at', null)
        .order('updated_at', { ascending: false })
      if (error) throw error
      return (data ?? []) as ProjectRow[]
    },
  })
}

export function useProject(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.project(id) : ['project', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<ProjectRow | null> => {
      const { data, error } = await supabase
        .from('projects')
        .select(PROJECT_COLS)
        .eq('id', id as string)
        .maybeSingle()
      if (error) throw error
      return data as ProjectRow | null
    },
  })
}
