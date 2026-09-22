import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/auth/SessionProvider'

/**
 * Pinned projects, stored in user_bookmarks (subject_kind='project').
 *
 * There was no dedicated pin table; user_bookmarks already models exactly this
 * — per-user, per-workspace, polymorphic subject — so pinning reuses it rather
 * than adding a table. Writes go direct: user_bookmarks has its own
 * insert/delete RLS policies scoped to the owning user.
 */
const SUBJECT_KIND = 'project'

export function usePinnedProjectIds(workspaceId: string | undefined) {
  const { session } = useSession()
  const uid = session?.user?.id
  return useQuery({
    queryKey: ['home', 'pins', workspaceId ?? '', uid ?? ''],
    enabled: Boolean(workspaceId && uid),
    queryFn: async (): Promise<string[]> => {
      const { data, error } = await supabase
        .from('user_bookmarks')
        .select('subject_id, created_at')
        .eq('workspace_id', workspaceId as string)
        .eq('subject_kind', SUBJECT_KIND)
        .order('created_at', { ascending: true })
      if (error) throw error
      return (data ?? []).map((r) => r.subject_id as string)
    },
  })
}

export function useTogglePin(workspaceId: string) {
  const qc = useQueryClient()
  const { session } = useSession()
  const uid = session?.user?.id
  return useMutation({
    mutationFn: async (input: { projectId: string; pinned: boolean }) => {
      if (input.pinned) {
        const { error } = await supabase
          .from('user_bookmarks')
          .delete()
          .eq('workspace_id', workspaceId)
          .eq('subject_kind', SUBJECT_KIND)
          .eq('subject_id', input.projectId)
        if (error) throw error
      } else {
        const { error } = await supabase.from('user_bookmarks').insert({
          user_id: uid as string,
          workspace_id: workspaceId,
          subject_kind: SUBJECT_KIND,
          subject_id: input.projectId,
        })
        if (error) throw error
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['home', 'pins'] }),
  })
}
