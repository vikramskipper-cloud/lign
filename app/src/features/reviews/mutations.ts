import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import {
  invalidateReviewsLists,
  invalidateReview,
  invalidateReviewInbox,
} from '@/features/shared/invalidate'
import { qk } from '@/lib/queryKeys'
import type { ReviewPolicy, ReviewerResponse } from './queries'

/**
 * All APP 006 mutations are round-trip except respond_to_review (optimistic).
 * Every success path invalidates dashboard + inbox + per-review caches.
 */

export interface CreateReviewInput {
  workspaceId: string
  projectId: string
  designAssetId: string
  versionId: string
  title: string
  description?: string | null
  reviewerWmIds?: string[]
  reviewerShIds?: string[]
  reviewerRequired?: boolean[]
  reviewerSequenceIndex?: number[]
  dueAt?: string | null
  open?: boolean
  coordinatorProfileId?: string | null
  policy?: ReviewPolicy
  quorumMin?: number | null
  requireCommentsResolved?: boolean
}

export function useCreateReview() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: CreateReviewInput): Promise<string> => {
      const { data, error } = await supabase.rpc('create_review', {
        p_project_id: input.projectId,
        p_design_asset_id: input.designAssetId,
        p_version_id: input.versionId,
        p_title: input.title.trim(),
        p_description: input.description?.trim() || null,
        p_reviewer_wm_ids: input.reviewerWmIds ?? [],
        p_reviewer_sh_ids: input.reviewerShIds ?? [],
        p_due_at: input.dueAt ?? null,
        p_open: input.open ?? false,
        p_coordinator_profile_id: input.coordinatorProfileId ?? null,
        p_policy: input.policy ?? 'parallel',
        p_quorum_min: input.quorumMin ?? null,
        p_require_comments_resolved: input.requireCommentsResolved ?? false,
        p_reviewer_required: input.reviewerRequired ?? [],
        p_reviewer_sequence_index: input.reviewerSequenceIndex ?? [],
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Review created')
      invalidateReviewsLists(qc, input.workspaceId, input.projectId)
      invalidateReviewInbox(qc, input.workspaceId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useOpenReview(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (reviewId: string) => {
      const { error } = await supabase.rpc('open_review', { p_review_id: reviewId })
      if (error) throw error
    },
    onSuccess: (_d, reviewId) => {
      toast.success('Review opened')
      invalidateReview(qc, reviewId)
      invalidateReviewsLists(qc, wsId, projId)
      invalidateReviewInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useSetReviewState(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { reviewId: string; target: 'waiting' | 'in_progress' }) => {
      const { error } = await supabase.rpc('set_review_state', {
        p_review_id: input.reviewId,
        p_target: input.target,
      })
      if (error) throw error
    },
    onSuccess: (_d, input) => {
      toast.success(input.target === 'waiting' ? 'Review paused' : 'Review resumed')
      invalidateReview(qc, input.reviewId)
      invalidateReviewsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useCompleteReview(wsId: string, projId: string, rootId?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      reviewId: string
      terminal: 'completed' | 'cancelled'
      cancellationReason?: string
      forced?: boolean
    }) => {
      const { error } = await supabase.rpc('complete_review', {
        p_review_id: input.reviewId,
        p_terminal: input.terminal,
        p_cancellation_reason: input.cancellationReason ?? null,
        p_forced: input.forced ?? false,
      })
      if (error) throw error
    },
    onSuccess: (_d, input) => {
      toast.success(input.terminal === 'completed' ? 'Review completed' : 'Review cancelled')
      invalidateReview(qc, input.reviewId, rootId)
      invalidateReviewsLists(qc, wsId, projId)
      invalidateReviewInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useReopenReview(wsId: string, projId: string, rootId?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      reviewId: string
      carryForwardAnnotations: boolean
      newVersionId?: string | null
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('reopen_review', {
        p_review_id: input.reviewId,
        p_carry_forward_annotations: input.carryForwardAnnotations,
        p_new_version_id: input.newVersionId ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (newId) => {
      toast.success('New round started')
      invalidateReview(qc, newId, rootId)
      invalidateReviewsLists(qc, wsId, projId)
      invalidateReviewInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useAddReviewer(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      reviewId: string
      wmId?: string | null
      shId?: string | null
      required: boolean
      sequenceIndex: number
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('add_reviewer', {
        p_review_id: input.reviewId,
        p_wm_id: input.wmId ?? null,
        p_sh_id: input.shId ?? null,
        p_required: input.required,
        p_sequence_index: input.sequenceIndex,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_d, input) => {
      toast.success('Reviewer added')
      invalidateReview(qc, input.reviewId)
      invalidateReviewsLists(qc, wsId, projId)
      invalidateReviewInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useRemoveReviewer(wsId: string, projId: string, reviewId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { participantId: string; reason: string }) => {
      const { error } = await supabase.rpc('remove_reviewer', {
        p_participant_id: input.participantId,
        p_reason: input.reason,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Reviewer removed')
      invalidateReview(qc, reviewId)
      invalidateReviewsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useReassignReviewer(wsId: string, projId: string, reviewId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      participantId: string
      newWmId?: string | null
      newShId?: string | null
    }) => {
      const { error } = await supabase.rpc('reassign_reviewer', {
        p_participant_id: input.participantId,
        p_new_wm_id: input.newWmId ?? null,
        p_new_sh_id: input.newShId ?? null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Reviewer reassigned')
      invalidateReview(qc, reviewId)
      invalidateReviewsLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useSetReviewerRequired(reviewId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { participantId: string; required: boolean }) => {
      const { error } = await supabase.rpc('set_reviewer_required', {
        p_participant_id: input.participantId,
        p_required: input.required,
      })
      if (error) throw error
    },
    onSuccess: () => {
      invalidateReview(qc, reviewId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useRespondToReview(wsId: string, projId: string, reviewId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { response: Extract<ReviewerResponse, 'signed_off' | 'commented' | 'declined'> }) => {
      const { error } = await supabase.rpc('respond_to_review', {
        p_review_id: reviewId,
        p_response: input.response,
      })
      if (error) throw error
    },
    onSuccess: (_d, input) => {
      toast.success(
        input.response === 'signed_off'
          ? 'Signed off'
          : input.response === 'declined'
            ? 'Declined'
            : 'Response recorded',
      )
      invalidateReview(qc, reviewId)
      invalidateReviewsLists(qc, wsId, projId)
      invalidateReviewInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useToggleBookmark(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      subjectKind: string
      subjectId: string
    }): Promise<boolean> => {
      const { data, error } = await supabase.rpc('toggle_bookmark', {
        p_subject_kind: input.subjectKind,
        p_subject_id: input.subjectId,
        p_workspace_id: wsId,
      })
      if (error) throw error
      return data as boolean
    },
    onSuccess: (bookmarked) => {
      toast.success(bookmarked ? 'Bookmarked' : 'Removed bookmark')
      qc.invalidateQueries({ queryKey: qk.bookmarks(wsId, 'review') })
      invalidateReviewsLists(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}
