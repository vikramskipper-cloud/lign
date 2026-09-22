import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'

/**
 * Approval responses from Home.
 *
 * NO UNDO. approval_responses carries approval_responses_no_update and
 * approval_responses_no_delete, both enforcing immutability — a response is
 * frozen at insert by design, because it is the audit record a client's lawyer
 * reads back later. The brief asked for Undo; the database will not allow it,
 * so the toast is plain and the row simply goes.
 *
 * The RPC records the responder's capacity itself (it resolves the approver
 * slot to a workspace_member or a stakeholder), which is why Home passes a
 * slot id and never a profile id — and why this path does not assume the
 * responder is internal.
 */
export type Decision = 'approved' | 'changes_requested'

export function useRespondToApproval() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: { slotId: string; decision: Decision; comment?: string | null }) => {
      const { error } = await supabase.rpc('respond_to_approval', {
        p_approver_slot_id: input.slotId,
        p_decision: input.decision,
        p_comment: input.comment?.trim() || null,
      })
      if (error) throw error
    },
    onSuccess: (_d, input) => {
      toast.success(input.decision === 'approved' ? 'Approved' : 'Changes requested')
      qc.invalidateQueries({ queryKey: ['home'] })
    },
    onError: (e) => toast.error(humanizeError(e)),
  })
}
