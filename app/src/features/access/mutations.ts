import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'
import { invalidateAccess } from '@/features/shared/invalidate'
import type { ProjectRole, WorkspaceRole } from './queries'

/**
 * APP 013 write layer — thin wrappers over the eight RPCs.
 *
 * Every authorization decision and every invariant lives in the database:
 * last-owner protection, self-lockout prevention, owner-only role grants,
 * and the cascade from workspace removal to project participation. Nothing
 * here re-implements them, and nothing here should start to — the UI hides
 * controls the caller cannot use, but the RPC is what actually says no.
 */

export interface InviteResult {
  invitationId: string
  /** Shown ONCE. Never persisted anywhere; only its sha256 reaches the database. */
  token: string
  expiresAt: string
}

/** The link an invitee opens. Copy-link delivery — there is no email infrastructure. */
export function inviteUrl(token: string): string {
  return `${window.location.origin}/invite/${token}`
}

export function useInviteMember(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { email: string; role: WorkspaceRole }): Promise<InviteResult> => {
      const { data, error } = await supabase.rpc('invite_workspace_member', {
        p_workspace_id: wsId,
        p_email: input.email.trim(),
        p_role: input.role,
        p_expires_in_days: 14,
      })
      if (error) throw error
      const row = Array.isArray(data) ? data[0] : data
      return {
        invitationId: row.out_invitation_id as string,
        token: row.out_token as string,
        expiresAt: row.out_expires_at as string,
      }
    },
    onSuccess: () => invalidateAccess(qc, wsId),
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useInviteStakeholder(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      email: string
      projectId: string
      role: ProjectRole
      displayName?: string | null
    }): Promise<InviteResult & { stakeholderId: string }> => {
      const { data, error } = await supabase.rpc('invite_stakeholder', {
        p_workspace_id: wsId,
        p_email: input.email.trim(),
        p_project_id: input.projectId,
        p_role: input.role,
        p_display_name: input.displayName?.trim() || null,
        p_expires_in_days: 14,
      })
      if (error) throw error
      const row = Array.isArray(data) ? data[0] : data
      return {
        invitationId: row.out_invitation_id as string,
        stakeholderId: row.out_stakeholder_id as string,
        token: row.out_token as string,
        expiresAt: row.out_expires_at as string,
      }
    },
    onSuccess: (_r, input) => invalidateAccess(qc, wsId, input.projectId),
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useRevokeInvitation(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (invitationId: string) => {
      const { error } = await supabase.rpc('revoke_invitation', { p_invitation_id: invitationId })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Invitation revoked')
      invalidateAccess(qc, wsId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useChangeMemberRole(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { memberId: string; role: WorkspaceRole }) => {
      const { error } = await supabase.rpc('change_workspace_member_role', {
        p_workspace_member_id: input.memberId,
        p_role: input.role,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Role updated')
      invalidateAccess(qc, wsId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useRemoveMember(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (memberId: string) => {
      const { error } = await supabase.rpc('remove_workspace_member', {
        p_workspace_member_id: memberId,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Member removed from the workspace and all its projects')
      invalidateAccess(qc, wsId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useRevokeStakeholder(wsId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (stakeholderId: string) => {
      const { error } = await supabase.rpc('revoke_stakeholder', {
        p_stakeholder_id: stakeholderId,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Stakeholder access revoked')
      invalidateAccess(qc, wsId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useAddParticipant(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      workspaceMemberId?: string | null
      stakeholderId?: string | null
      role: ProjectRole
    }) => {
      const { error } = await supabase.rpc('add_project_participant', {
        p_project_id: projId,
        p_workspace_member_id: input.workspaceMemberId ?? null,
        p_stakeholder_id: input.stakeholderId ?? null,
        p_role: input.role,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Added to the project')
      invalidateAccess(qc, wsId, projId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useChangeParticipantRole(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { participantId: string; role: ProjectRole }) => {
      const { error } = await supabase.rpc('change_project_participant_role', {
        p_participant_id: input.participantId,
        p_role: input.role,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Project role updated')
      invalidateAccess(qc, wsId, projId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}

export function useRemoveParticipant(wsId: string, projId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (participantId: string) => {
      const { error } = await supabase.rpc('remove_project_participant', {
        p_participant_id: participantId,
      })
      if (error) throw error
    },
    onSuccess: () => {
      toast.success('Removed from the project')
      invalidateAccess(qc, wsId, projId)
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}
