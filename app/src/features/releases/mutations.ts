import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import {
  invalidateRelease,
  invalidateReleaseInbox,
  invalidateReleasesLists,
} from '@/features/shared/invalidate'
import { qk } from '@/lib/queryKeys'
import type { ReleaseType } from './queries'

/**
 * APP 009 mutations. Every mutation wraps one of the 8 write RPCs.
 * No optimistic updates — publish is server-authoritative (Freeze Index G-30).
 */

export interface CreateReleaseDraftInput {
  workspaceId: string
  projectId: string
  name: string
  notes?: string | null
  channel?: string | null
  releaseType?: ReleaseType | null
}

export function useCreateReleaseDraft(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: CreateReleaseDraftInput): Promise<string> => {
      const { data, error } = await supabase.rpc('create_release_draft', {
        p_project_id: input.projectId,
        p_name: input.name,
        p_notes: input.notes ?? null,
        p_channel: input.channel ?? null,
        p_release_type: input.releaseType ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: () => {
      toast.success('Release draft created')
      invalidateReleasesLists(qc, wsId, projId)
      invalidateReleaseInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export interface AddReleaseItemInput {
  releaseId: string
  designAssetId: string
  versionId: string
  notes?: string | null
  sortOrder?: number | null
}

export function useAddReleaseItem(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: AddReleaseItemInput): Promise<string> => {
      const { data, error } = await supabase.rpc('add_release_item', {
        p_release_id: input.releaseId,
        p_design_asset_id: input.designAssetId,
        p_version_id: input.versionId,
        p_notes: input.notes ?? null,
        p_sort_order: input.sortOrder ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Item added')
      invalidateRelease(qc, input.releaseId)
      qc.invalidateQueries({ queryKey: qk.releaseItems(input.releaseId) })
      invalidateReleasesLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useRemoveReleaseItem(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      releaseId: string
      versionId: string
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('remove_release_item', {
        p_release_id: input.releaseId,
        p_version_id: input.versionId,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Item removed')
      invalidateRelease(qc, input.releaseId)
      qc.invalidateQueries({ queryKey: qk.releaseItems(input.releaseId) })
      invalidateReleasesLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useReorderReleaseItems(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      releaseId: string
      orderedVersionIds: string[]
    }): Promise<number> => {
      const { data, error } = await supabase.rpc('reorder_release_items', {
        p_release_id: input.releaseId,
        p_ordered_version_ids: input.orderedVersionIds,
      })
      if (error) throw error
      return data as number
    },
    onSuccess: (_n, input) => {
      toast.success('Items reordered')
      qc.invalidateQueries({ queryKey: qk.releaseItems(input.releaseId) })
      invalidateReleasesLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function useDiscardReleaseDraft(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (releaseId: string): Promise<string> => {
      const { data, error } = await supabase.rpc('discard_release_draft', {
        p_release_id: releaseId,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, releaseId) => {
      toast.success('Draft discarded')
      invalidateRelease(qc, releaseId)
      invalidateReleasesLists(qc, wsId, projId)
      invalidateReleaseInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

export function usePublishRelease(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      releaseId: string
      releaseType?: ReleaseType | null
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('publish_release', {
        p_release_id: input.releaseId,
        p_release_type: input.releaseType ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Release published')
      invalidateRelease(qc, input.releaseId)
      qc.invalidateQueries({ queryKey: qk.releaseEvidence(input.releaseId) })
      qc.invalidateQueries({ queryKey: qk.releaseItems(input.releaseId) })
      qc.invalidateQueries({ queryKey: qk.releaseActivity(input.releaseId) })
      invalidateReleasesLists(qc, wsId, projId)
      invalidateReleaseInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

/** Calls the CREATE OR REPLACE-extended finalize_release(uuid, text). */
export function useFinalizeRelease(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      releaseId: string
      releaseType?: ReleaseType | null
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('finalize_release', {
        p_release_id: input.releaseId,
        p_release_type: input.releaseType ?? null,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Release finalized')
      invalidateRelease(qc, input.releaseId)
      qc.invalidateQueries({ queryKey: qk.releaseEvidence(input.releaseId) })
      qc.invalidateQueries({ queryKey: qk.releaseItems(input.releaseId) })
      qc.invalidateQueries({ queryKey: qk.releaseActivity(input.releaseId) })
      invalidateReleasesLists(qc, wsId, projId)
      invalidateReleaseInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

/** Calls the CREATE OR REPLACE-extended withdraw_release(uuid, text, boolean). */
export function useWithdrawRelease(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      releaseId: string
      reason: string
      adminOverride?: boolean
    }): Promise<string> => {
      const { data, error } = await supabase.rpc('withdraw_release', {
        p_release_id: input.releaseId,
        p_reason: input.reason,
        p_admin_override: input.adminOverride ?? false,
      })
      if (error) throw error
      return data as string
    },
    onSuccess: (_id, input) => {
      toast.success('Release withdrawn')
      invalidateRelease(qc, input.releaseId)
      qc.invalidateQueries({ queryKey: qk.releaseActivity(input.releaseId) })
      invalidateReleasesLists(qc, wsId, projId)
      invalidateReleaseInbox(qc, wsId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}

/**
 * Draft-time metadata edit uses the frozen RLS UPDATE policy directly
 * (name / notes / channel / effective_at / release_type). No RPC wrapper in v1
 * per proposal §14.9 (`edit_release_metadata` reserved for Wave 4).
 */
export function useEditReleaseDraftMetadata(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      releaseId: string
      name?: string
      notes?: string | null
      channel?: string | null
      releaseType?: ReleaseType | null
      effectiveAt?: string | null
    }): Promise<boolean> => {
      const patch: Record<string, unknown> = {}
      if (input.name !== undefined) patch.name = input.name
      if (input.notes !== undefined) patch.notes = input.notes
      if (input.channel !== undefined) patch.channel = input.channel
      if (input.releaseType !== undefined) patch.release_type = input.releaseType
      if (input.effectiveAt !== undefined) patch.effective_at = input.effectiveAt
      if (Object.keys(patch).length === 0) return false
      const { error } = await supabase
        .from('releases')
        .update(patch as never)
        .eq('id', input.releaseId)
      if (error) throw error
      return true
    },
    onSuccess: (ok, input) => {
      if (ok) toast.success('Release updated')
      invalidateRelease(qc, input.releaseId)
      invalidateReleasesLists(qc, wsId, projId)
    },
    onError: (err) => toast.error(humanizeError(err)),
  })
}
