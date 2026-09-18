import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'

export interface CommentRow {
  id: string
  workspace_id: string
  parent_comment_id: string | null
  body: string
  author_profile_id: string | null
  resolved_at: string | null
  deleted_at: string | null
  target_version_id: string | null
  target_annotation_id: string | null
  target_review_id: string | null
  target_change_id: string | null
  target_decision_id: string | null
  target_design_asset_id: string | null
  target_approval_request_id: string | null
  created_at: string
  updated_at: string
  author: { id: string; display_name: string; avatar_url: string | null } | null
}

const SELECT = `
  id, workspace_id, parent_comment_id, body, author_profile_id, resolved_at, deleted_at,
  target_version_id, target_annotation_id, target_review_id, target_change_id,
  target_decision_id, target_design_asset_id, target_approval_request_id,
  created_at, updated_at,
  author:profiles!comments_author_profile_id_fkey ( id, display_name, avatar_url )
`

/**
 * All non-deleted comments whose target is either:
 *   (a) this version directly (target_version_id = versionId), or
 *   (b) an annotation on this version (target_annotation_id ∈ annotations of versionId).
 *
 * Replies (parent_comment_id IS NOT NULL) are included; grouping into threads
 * is a client-side reduce in CommentsPanel.
 *
 * Two SELECTs are issued in parallel: one for version-scoped comments, one for
 * annotation-scoped. Their union is returned.
 */
export function useCommentsForVersion(
  versionId: string | undefined,
  annotationIds: string[],
) {
  return useQuery({
    queryKey: versionId
      ? [...qk.commentsForVersion(versionId), annotationIds.slice().sort().join(',')]
      : ['asset-version', 'none', 'comments'],
    enabled: Boolean(versionId),
    queryFn: async (): Promise<CommentRow[]> => {
      const [versionScoped, annotationScoped] = await Promise.all([
        supabase
          .from('comments')
          .select(SELECT)
          .eq('target_version_id', versionId as string)
          .is('deleted_at', null)
          .order('created_at', { ascending: true }),
        annotationIds.length > 0
          ? supabase
              .from('comments')
              .select(SELECT)
              .in('target_annotation_id', annotationIds)
              .is('deleted_at', null)
              .order('created_at', { ascending: true })
          : Promise.resolve({ data: [], error: null } as {
              data: unknown[]
              error: null
            }),
      ])
      if (versionScoped.error) throw versionScoped.error
      if (annotationScoped.error) throw annotationScoped.error
      const merged = [
        ...((versionScoped.data ?? []) as unknown as CommentRow[]),
        ...((annotationScoped.data ?? []) as unknown as CommentRow[]),
      ]
      // De-dup on the off chance PostgREST returns overlap (shouldn't).
      const seen = new Set<string>()
      return merged.filter((c) => {
        if (seen.has(c.id)) return false
        seen.add(c.id)
        return true
      })
    },
  })
}

export function useComment(id: string | undefined) {
  return useQuery({
    queryKey: id ? qk.comment(id) : ['comment', 'none'],
    enabled: Boolean(id),
    queryFn: async (): Promise<CommentRow | null> => {
      const { data, error } = await supabase
        .from('comments')
        .select(SELECT)
        .eq('id', id as string)
        .maybeSingle()
      if (error) throw error
      return (data as unknown as CommentRow | null) ?? null
    },
  })
}

export interface CommentEditRow {
  id: string
  comment_id: string
  revision: number
  previous_body: string
  edited_by_profile_id: string | null
  edited_at: string
}

export function useCommentEdits(commentId: string | undefined) {
  return useQuery({
    queryKey: commentId ? qk.commentEdits(commentId) : ['comment', 'none', 'edits'],
    enabled: Boolean(commentId),
    queryFn: async (): Promise<CommentEditRow[]> => {
      const { data, error } = await supabase
        .from('comment_edits')
        .select('id, comment_id, revision, previous_body, edited_by_profile_id, edited_at')
        .eq('comment_id', commentId as string)
        .order('revision', { ascending: false })
      if (error) throw error
      return (data ?? []) as CommentEditRow[]
    },
  })
}
