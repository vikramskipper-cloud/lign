import * as React from 'react'
import { useParams, useSearchParams } from 'react-router'
import { useWorkspaces } from '@/shell/queries'
import { persistLastWorkspace, readLastWorkspace } from '@/shell/WorkspaceSwitcher'

/**
 * Which workspace the chrome is currently showing.
 *
 * Precedence: the URL's :ws_id, then ?ws=, then the last one used, then the
 * first membership. The URL always wins — a link someone sent you must open
 * the workspace it names, not the one you happened to look at last.
 *
 * ?ws= and the stored value are both validated against the caller's actual
 * memberships before use, so a stale id (workspace left, workspace deleted)
 * falls through instead of resolving to a workspace that 404s on every query.
 *
 * Shared by AppShell and HomeScreen so the rail and the page it frames can
 * never disagree about which workspace is in scope.
 */
export function useActiveWorkspaceId(): {
  workspaceId: string | undefined
  isLoading: boolean
  hasNone: boolean
} {
  const { ws_id } = useParams<{ ws_id?: string }>()
  const [params] = useSearchParams()
  const workspaces = useWorkspaces()

  const all = workspaces.data ?? []
  const known = (id: string | null | undefined) => Boolean(id && all.some((w) => w.id === id))

  const wsParam = params.get('ws')
  const stored = readLastWorkspace()

  const workspaceId =
    ws_id ??
    (known(wsParam) ? (wsParam as string) : undefined) ??
    (known(stored) ? (stored as string) : undefined) ??
    all[0]?.id

  React.useEffect(() => {
    if (workspaceId) persistLastWorkspace(workspaceId)
  }, [workspaceId])

  return {
    workspaceId,
    isLoading: workspaces.isLoading,
    hasNone: !workspaces.isLoading && all.length === 0,
  }
}
