import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import {
  invalidateRequirementsLists,
  invalidateRequirement,
  invalidateRequirementInbox,
} from '@/features/shared/invalidate'
import { qk } from '@/lib/queryKeys'
import type {
  AssessmentStatus,
  RequirementCategoryKind,
  RequirementPriority,
  RequirementSourceKind,
} from './queries'

/**
 * APP 008 mutations. Every mutation wraps one of the 6 frozen workflow RPCs
 * (create_requirement / edit_requirement / archive_requirement /
 *  supersede_requirement / set_requirement_applicability /
 *  assess_version_requirement). No optimistic updates — assessment casts are
 * authoritative on the server (Freeze Index §17.5).
 */

export interface CreateRequirementInput {
  workspaceId: string
  projectId: string
  title: string
  description?: string | null
  category?: string | null
  source?: string | null
  sourceRef?: string | null
  parentRequirementId?: string | null
  status?: 'draft' | 'active'
  priority?: RequirementPriority | null
  sourceKind?: RequirementSourceKind | null
  categoryKind?: RequirementCategoryKind | null
  ownerProfileId?: string | null
  verificationMethod?:
    | 'inspection'
    | 'test'
    | 'analysis'
    | 'demonstration'
    | null
  dueAt?: string | null
}

export function useCreateRequirement(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (
      input: CreateRequirementInput,
    ): Promise<{ requirementId: string; code: string }> => {
      const { data, error } = await supabase.rpc('create_requirement', {
        p_project_id: input.projectId,
        p_workspace_id: input.workspaceId,
        p_title: input.title,
        p_description: input.description ?? null,
        p_category: input.category ?? null,
        p_source: input.source ?? null,
        p_source_ref: input.sourceRef ?? null,
        p_parent_requirement_id: input.parentRequirementId ?? null,
        p_status: input.status ?? 'draft',
        p_priority: input.priority ?? null,
        p_source_kind: input.sourceKind ?? null,
        p_category_kind: input.categoryKind ?? null,
        p_owner_profile_id: input.ownerProfileId ?? null,
        p_verification_method: input.verificationMethod ?? null,
        p_due_at: input.dueAt ?? null,
      })
      if (error) throw error
      const row = (data as { out_requirement_id: string; out_code: string }[])?.[0]
      return { requirementId: row.out_requirement_id, code: row.out_code }
    },
    onSuccess: () => {
      toast.success('Requirement created')
      invalidateRequirementsLists(qc, wsId, projId)
      invalidateRequirementInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface EditRequirementInput {
  requirementId: string
  title?: string | null
  description?: string | null
  category?: string | null
  source?: string | null
  sourceRef?: string | null
  status?: 'draft' | 'active' | null
  priority?: RequirementPriority | null
  sourceKind?: RequirementSourceKind | null
  categoryKind?: RequirementCategoryKind | null
  ownerProfileId?: string | null
  verificationMethod?:
    | 'inspection'
    | 'test'
    | 'analysis'
    | 'demonstration'
    | null
  dueAt?: string | null
}

export function useEditRequirement(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: EditRequirementInput): Promise<boolean> => {
      const { data, error } = await supabase.rpc('edit_requirement', {
        p_requirement_id: input.requirementId,
        p_title: input.title ?? null,
        p_description: input.description ?? null,
        p_category: input.category ?? null,
        p_source: input.source ?? null,
        p_source_ref: input.sourceRef ?? null,
        p_status: input.status ?? null,
        p_priority: input.priority ?? null,
        p_source_kind: input.sourceKind ?? null,
        p_category_kind: input.categoryKind ?? null,
        p_owner_profile_id: input.ownerProfileId ?? null,
        p_verification_method: input.verificationMethod ?? null,
        p_due_at: input.dueAt ?? null,
      })
      if (error) throw error
      const row = (data as { out_updated: boolean }[])?.[0]
      return Boolean(row?.out_updated)
    },
    onSuccess: (updated, input) => {
      if (updated) toast.success('Requirement updated')
      invalidateRequirement(qc, input.requirementId)
      invalidateRequirementsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useArchiveRequirement(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (requirementId: string): Promise<boolean> => {
      const { data, error } = await supabase.rpc('archive_requirement', {
        p_requirement_id: requirementId,
      })
      if (error) throw error
      return Boolean(data)
    },
    onSuccess: (didArchive, requirementId) => {
      if (didArchive) toast.success('Requirement archived')
      invalidateRequirement(qc, requirementId)
      invalidateRequirementsLists(qc, wsId, projId)
      invalidateRequirementInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface SupersedeRequirementInput {
  oldRequirementId: string
  newRequirementId: string
}

export function useSupersedeRequirement(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: SupersedeRequirementInput): Promise<boolean> => {
      const { data, error } = await supabase.rpc('supersede_requirement', {
        p_old_requirement_id: input.oldRequirementId,
        p_new_requirement_id: input.newRequirementId,
      })
      if (error) throw error
      return Boolean(data)
    },
    onSuccess: (_ok, input) => {
      toast.success('Superseded')
      invalidateRequirement(qc, input.oldRequirementId)
      invalidateRequirement(qc, input.newRequirementId)
      invalidateRequirementsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface SetApplicabilityInput {
  requirementId: string
  designAssetIds: string[]
}

export function useSetRequirementApplicability(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (
      input: SetApplicabilityInput,
    ): Promise<{ added: number; removed: number; kept: number }> => {
      const { data, error } = await supabase.rpc(
        'set_requirement_applicability',
        {
          p_requirement_id: input.requirementId,
          p_design_asset_ids: input.designAssetIds,
        },
      )
      if (error) throw error
      const row = (data as {
        out_added: number
        out_removed: number
        out_kept: number
      }[])?.[0]
      return {
        added: row?.out_added ?? 0,
        removed: row?.out_removed ?? 0,
        kept: row?.out_kept ?? 0,
      }
    },
    onSuccess: (_r, input) => {
      toast.success('Applicability updated')
      invalidateRequirement(qc, input.requirementId)
      qc.invalidateQueries({
        queryKey: qk.requirementApplicability(input.requirementId),
      })
      invalidateRequirementsLists(qc, wsId, projId)
      qc.invalidateQueries({
        predicate: (q) => {
          const k = q.queryKey as unknown[]
          return (
            Array.isArray(k) && k[0] === 'requirements' && k[1] === 'for-asset'
          )
        },
      })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface AssessVersionInput {
  assetVersionId: string
  requirementId: string
  status: AssessmentStatus
  note?: string | null
}

export function useAssessVersionRequirement(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (
      input: AssessVersionInput,
    ): Promise<{ assessmentId: string; action: 'created' | 'updated' }> => {
      const { data, error } = await supabase.rpc('assess_version_requirement', {
        p_asset_version_id: input.assetVersionId,
        p_requirement_id: input.requirementId,
        p_status: input.status,
        p_note: input.note ?? null,
      })
      if (error) throw error
      const row = (data as { out_assessment_id: string; out_action: string }[])?.[0]
      return {
        assessmentId: row.out_assessment_id,
        action: row.out_action as 'created' | 'updated',
      }
    },
    onSuccess: (_r, input) => {
      toast.success('Assessment recorded')
      invalidateRequirement(qc, input.requirementId)
      qc.invalidateQueries({
        queryKey: qk.requirementAssessments(input.requirementId),
      })
      qc.invalidateQueries({
        queryKey: qk.assessmentsForVersion(input.assetVersionId),
      })
      qc.invalidateQueries({
        queryKey: qk.releaseReadinessForVersion(input.assetVersionId),
      })
      qc.invalidateQueries({
        predicate: (q) => {
          const k = q.queryKey as unknown[]
          return (
            Array.isArray(k) && k[0] === 'requirements' && k[1] === 'for-asset'
          )
        },
      })
      invalidateRequirementInbox(qc, wsId)
      qc.invalidateQueries({
        queryKey: qk.requirementHistory(input.requirementId),
      })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

/** Toggle a workspace bookmark on a requirement (reuses APP 006 RPC). */
export function useToggleRequirementBookmark(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { subjectId: string }): Promise<boolean> => {
      const { data, error } = await supabase.rpc('toggle_bookmark', {
        p_subject_kind: 'requirement',
        p_subject_id: input.subjectId,
        p_workspace_id: wsId,
      })
      if (error) throw error
      return data as boolean
    },
    onSuccess: (bookmarked) => {
      toast.success(bookmarked ? 'Bookmarked' : 'Removed bookmark')
      qc.invalidateQueries({ queryKey: qk.bookmarks(wsId, 'requirement') })
      invalidateRequirementsLists(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

/** Comment insertion targeting a requirement (Discussions tab). */
export interface RequirementCommentInput {
  requirementId: string
  workspaceId: string
  body: string
  parentCommentId?: string | null
}

export function useCreateRequirementComment() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: RequirementCommentInput): Promise<string> => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) throw new Error('Not signed in')
      const { data, error } = await supabase
        .from('comments')
        .insert({
          workspace_id: input.workspaceId,
          body: input.body,
          author_profile_id: user.id,
          target_requirement_id: input.requirementId,
          parent_comment_id: input.parentCommentId ?? null,
        } as never)
        .select('id')
        .single()
      if (error) throw error
      return (data as { id: string }).id
    },
    onSuccess: (_id, input) => {
      qc.invalidateQueries({
        queryKey: qk.requirementDiscussions(input.requirementId),
      })
      qc.invalidateQueries({ queryKey: qk.requirementTrace(input.requirementId) })
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}
