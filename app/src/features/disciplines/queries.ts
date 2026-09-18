import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export interface DisciplineRow {
  id: string
  workspace_id: string
  project_id: string
  name: string
  description: string | null
  sort_order: number
  status: 'active' | 'archived'
  archived_at: string | null
  created_at: string
  updated_at: string
}

const COLS =
  'id, workspace_id, project_id, name, description, sort_order, status, archived_at, created_at, updated_at'

export function useDisciplines(projId: string | undefined) {
  return useQuery({
    queryKey: projId ? qk.disciplines(projId) : ['project', 'none', 'disciplines'],
    enabled: Boolean(projId),
    queryFn: async (): Promise<DisciplineRow[]> => {
      const { data, error } = await supabase
        .from('disciplines')
        .select(COLS)
        .eq('project_id', projId as string)
        .eq('status', 'active')
        .order('sort_order', { ascending: true })
        .order('name', { ascending: true })
      if (error) throw error
      return (data ?? []) as DisciplineRow[]
    },
  })
}
