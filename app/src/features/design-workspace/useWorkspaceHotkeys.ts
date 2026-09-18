import * as React from 'react'

interface Handlers {
  onNewComment?: () => void
  onAddPin?: () => void
  onEscape?: () => void
  // APP 006 additive
  onNewReview?: () => void
  onFocusRoster?: () => void
  onSignOff?: () => void
  // APP 007 additive
  onApprove?: () => void
  onReject?: () => void
  onAbstain?: () => void
  // APP 008 additive
  onNewRequirement?: () => void
  onFocusRequirementSearch?: () => void
  // APP 010 additive (bell + inbox)
  onNavigateInbox?: () => void
  onArchiveNotification?: () => void
  onDismissNotification?: () => void
}

/**
 * Workspace-wide keyboard shortcuts.
 *   C          → onNewComment      (APP 005)
 *   P          → onAddPin          (APP 005)
 *   Esc        → onEscape          (APP 005)
 *   R          → onNewReview       (APP 006)
 *   E          → onFocusRoster     (APP 006, in Review Detail)
 *   Shift+↵    → onSignOff         (APP 006, reviewer submit as signed_off)
 */
export function useWorkspaceHotkeys({
  onNewComment,
  onAddPin,
  onEscape,
  onNewReview,
  onFocusRoster,
  onSignOff,
  onApprove,
  onReject,
  onAbstain,
  onNewRequirement,
  onFocusRequirementSearch,
  onNavigateInbox,
  onArchiveNotification,
  onDismissNotification,
}: Handlers) {
  React.useEffect(() => {
    const isTypingTarget = (t: EventTarget | null): boolean => {
      if (!(t instanceof HTMLElement)) return false
      const tag = t.tagName
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true
      if (t.isContentEditable) return true
      return false
    }

    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (e.key === 'Escape') {
        onEscape?.()
        return
      }
      if (e.shiftKey && e.key === 'Enter') {
        if (onSignOff) {
          e.preventDefault()
          onSignOff()
        }
        return
      }
      if (isTypingTarget(e.target)) return
      if (e.shiftKey) {
        // APP 007: Shift+A → abstain
        if (e.key === 'A' || e.key === 'a') {
          if (onAbstain) {
            e.preventDefault()
            onAbstain()
          }
        }
        // APP 010: Shift+N → navigate to Inbox (workspace scope)
        if (e.key === 'N' || e.key === 'n') {
          if (onNavigateInbox) {
            e.preventDefault()
            onNavigateInbox()
          }
        }
        return
      }
      switch (e.key) {
        case 'c':
        case 'C':
          e.preventDefault()
          onNewComment?.()
          break
        case 'p':
        case 'P':
          e.preventDefault()
          onAddPin?.()
          break
        case 'r':
        case 'R':
          e.preventDefault()
          onNewReview?.()
          break
        case 'e':
        case 'E':
          e.preventDefault()
          onFocusRoster?.()
          break
        case 'a':
        case 'A':
          if (onApprove) {
            e.preventDefault()
            onApprove()
          }
          break
        case 'x':
        case 'X':
          if (onReject) {
            e.preventDefault()
            onReject()
          }
          break
        case 'n':
        case 'N':
          if (onNewRequirement) {
            e.preventDefault()
            onNewRequirement()
          }
          break
        case '/':
          if (onFocusRequirementSearch) {
            e.preventDefault()
            onFocusRequirementSearch()
          }
          break
        // APP 010: E → archive focused notification card (mnemonic "email archive")
        // Handled here only if a card focus handler was passed; otherwise E falls
        // through to onFocusRoster (APP 006 review roster focus).
        // APP 010: Backspace/Delete → dismiss focused notification card
      }
      if ((e.key === 'Backspace' || e.key === 'Delete') && onDismissNotification) {
        e.preventDefault()
        onDismissNotification()
      }
      if ((e.key === 'e' || e.key === 'E') && onArchiveNotification && !onFocusRoster) {
        e.preventDefault()
        onArchiveNotification()
      }
    }

    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [
    onNewComment, onAddPin, onEscape, onNewReview, onFocusRoster, onSignOff,
    onApprove, onReject, onAbstain, onNewRequirement, onFocusRequirementSearch,
    onNavigateInbox, onArchiveNotification, onDismissNotification,
  ])
}
