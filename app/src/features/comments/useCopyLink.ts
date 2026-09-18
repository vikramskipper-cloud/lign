import * as React from 'react'
import { toast } from 'sonner'

export type LinkKind =
  | 'comment'
  | 'annotation'
  | 'review'
  | 'reviewer'
  | 'approval'
  | 'approver'
  // APP 008 — Requirements
  | 'requirement'
  | 'requirement-code'
  // APP 010 — Notifications
  | 'notification'
  | 'inbox'

/**
 * Copies a canonical /deep/<kind>/:id URL to the clipboard.
 * Uses the current origin so links are portable across environments.
 * Falls back to window.prompt() when clipboard access is unavailable.
 */
export function useCopyLink() {
  return React.useCallback(async (kind: LinkKind, id: string) => {
    const url = `${window.location.origin}/deep/${kind}/${id}`
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(url)
        toast.success('Link copied')
        return
      }
      throw new Error('clipboard unavailable')
    } catch {
      window.prompt('Copy link:', url)
    }
  }, [])
}
