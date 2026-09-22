import * as React from 'react'
import { Link, useNavigate, useParams } from 'react-router'
import { AlertTriangle, CheckCircle2 } from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { Button } from '@/ui/button'
import { LoadingPage } from '@/ui/loading-page'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import { humanizeError } from '@/features/shared/errors'

type State =
  | { kind: 'idle' }
  | { kind: 'claiming' }
  | { kind: 'done'; workspaceId: string | null }
  | { kind: 'error'; message: string }

/**
 * Invitation claim. Previously a placeholder that displayed the token and
 * called nothing, which left the whole invite flow non-functional even though
 * both RPCs existed.
 *
 * The token does not say whether it is a member or a stakeholder invitation,
 * and there is no read RPC to ask. So we try accept_invitation first and fall
 * back to claim_stakeholder_invitation. Both verify the token hash, the expiry
 * and that the invitation email matches the signed-in account, so a wrong
 * guess fails safely — it cannot claim anything it should not.
 */
export function InviteClaimScreen() {
  const { token } = useParams<{ token: string }>()
  const { session, isLoading, user } = useSession()
  const navigate = useNavigate()
  const [state, setState] = React.useState<State>({ kind: 'idle' })

  const returnTo = `/invite/${token ?? ''}`

  const claim = React.useCallback(async () => {
    if (!token) return
    setState({ kind: 'claiming' })

    const asMember = await supabase.rpc('accept_invitation', { p_token: token })
    if (!asMember.error) {
      const { data } = await supabase
        .from('workspace_members')
        .select('workspace_id')
        .eq('id', asMember.data as string)
        .maybeSingle()
      setState({ kind: 'done', workspaceId: (data?.workspace_id as string) ?? null })
      return
    }

    const asStakeholder = await supabase.rpc('claim_stakeholder_invitation', { p_token: token })
    if (!asStakeholder.error) {
      const { data } = await supabase
        .from('stakeholders')
        .select('workspace_id')
        .eq('id', asStakeholder.data as string)
        .maybeSingle()
      setState({ kind: 'done', workspaceId: (data?.workspace_id as string) ?? null })
      return
    }

    // Report the stakeholder error: if this token were a member invitation,
    // the first call would have succeeded or failed for the same reason.
    setState({ kind: 'error', message: humanizeError(asStakeholder.error) })
  }, [token])

  if (isLoading) return <LoadingPage label="Loading…" />

  return (
    <div className="flex min-h-full items-center justify-center bg-[--color-bg] p-6">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>You&apos;ve been invited to Lign</CardTitle>
          <CardDescription>
            {session
              ? `Signed in as ${user?.email}. The invitation must have been sent to this address.`
              : 'Sign in or create an account with the email address that received this invitation.'}
          </CardDescription>
        </CardHeader>

        <CardContent className="space-y-4">
          {!token && (
            <p className="text-sm text-[--color-danger]">This link is missing its token.</p>
          )}

          {!session && token && (
            <div className="flex gap-2">
              <Button asChild className="flex-1">
                <Link to={`/signup?returnTo=${encodeURIComponent(returnTo)}`}>Create account</Link>
              </Button>
              <Button asChild variant="secondary" className="flex-1">
                <Link to={`/signin?returnTo=${encodeURIComponent(returnTo)}`}>Sign in</Link>
              </Button>
            </div>
          )}

          {session && token && state.kind !== 'done' && (
            <>
              <Button
                className="w-full"
                onClick={claim}
                disabled={state.kind === 'claiming'}
              >
                {state.kind === 'claiming' ? 'Accepting…' : 'Accept invitation'}
              </Button>
              {state.kind === 'error' && (
                <div className="flex gap-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface-2] p-3 text-sm">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-[--color-danger]" />
                  <div>
                    <p>{state.message}</p>
                    <p className="mt-1 text-xs text-[--color-text-muted]">
                      Invitations are single-use, expire, and only work for the exact email they
                      were sent to. Ask whoever invited you to issue a new link.
                    </p>
                  </div>
                </div>
              )}
            </>
          )}

          {state.kind === 'done' && (
            <div className="space-y-3">
              <div className="flex items-center gap-2 text-sm">
                <CheckCircle2 className="h-4 w-4 text-[--color-success]" />
                <span>You&apos;re in.</span>
              </div>
              <Button
                className="w-full"
                onClick={() =>
                  navigate(state.workspaceId ? `/workspace/${state.workspaceId}` : '/', {
                    replace: true,
                  })
                }
              >
                Continue
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
