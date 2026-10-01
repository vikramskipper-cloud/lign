import * as React from 'react'
import { Navigate, useNavigate, useParams } from 'react-router'
import { useSession } from '@/auth/SessionProvider'
import { AuthShell, BuildString, Wordmark } from '@/auth/AuthShell'
import { FullPageLoader } from '@/ui/full-page-loader'
import { useAcceptOrgInvitation } from '@/shell/orgQueries'
import '@/styles/auth-theme.css'

/**
 * What an organisation invite link opens.
 *
 * The token names an ADDRESS, not a person: accept_org_invitation refuses
 * unless the signed-in account's email matches the invitation. That is the
 * whole reason a forwarded link cannot hand over access, so this screen never
 * tries to be clever about who is holding it — it signs you in first and lets
 * the database decide.
 *
 * Signed out, it bounces to /sign-in with ?returnTo= pointing back here, so
 * the claim resumes after login rather than being lost.
 */
export function OrgInviteClaimScreen() {
  const { token } = useParams<{ token: string }>()
  const { session, user, isLoading } = useSession()
  const accept = useAcceptOrgInvitation()
  const navigate = useNavigate()

  const [error, setError] = React.useState<string | null>(null)
  const [done, setDone] = React.useState(false)
  const attempted = React.useRef(false)

  React.useEffect(() => {
    if (!session || !token || attempted.current) return
    attempted.current = true
    accept.mutate(token, {
      onSuccess: () => {
        setDone(true)
        navigate('/dashboard', { replace: true })
      },
      onError: (err) => {
        const msg = (err as { message?: string } | null)?.message ?? ''
        setError(
          msg.includes('does not match')
            ? 'This invitation was sent to a different email address. Sign in as that address to accept it.'
            : msg.includes('not found')
              ? 'This invitation has expired, been revoked, or was already used.'
              : "Couldn't accept the invitation. Check your connection and try again.",
        )
      },
    })
  }, [session, token, accept, navigate])

  if (isLoading) return <FullPageLoader label="Signing you in" />
  if (!token) return <Navigate to="/dashboard" replace />
  if (!session) {
    return <Navigate to={`/sign-in?returnTo=${encodeURIComponent(`/org-invite/${token}`)}`} replace />
  }
  if (done) return <FullPageLoader label="Joining" />

  return (
    <AuthShell>
      <div style={{ width: '100%', maxWidth: 408 }}>
        <div className="lg:hidden" style={{ marginBottom: 28 }}>
          <Wordmark />
        </div>

        {error ? (
          <>
            <h1 className="auth-display" style={{ fontSize: 'clamp(28px, 5vw, 34px)', lineHeight: 1.1, margin: 0 }}>
              Can&apos;t accept this invitation
            </h1>
            <div
              role="alert"
              style={{
                marginTop: 18, background: 'var(--error-bg)', border: '1px solid var(--error-border)',
                borderRadius: 'var(--radius-field)', padding: '11px 13px', fontSize: 13.5,
                color: 'var(--error-text)',
              }}
            >
              {error}
            </div>
            <p style={{ margin: '14px 0 0', fontSize: 13, color: 'var(--muted)' }}>
              You&apos;re signed in as {user?.email}. Ask whoever invited you to send a new link.
            </p>
            <button
              type="button"
              className="auth-btn-primary"
              style={{ marginTop: 22 }}
              onClick={() => navigate('/dashboard', { replace: true })}
            >
              Continue to LIGN
            </button>
          </>
        ) : (
          <>
            <h1 className="auth-display" style={{ fontSize: 'clamp(28px, 5vw, 34px)', lineHeight: 1.1, margin: 0 }}>
              Joining the organisation…
            </h1>
            <p style={{ margin: '12px 0 0', fontSize: 15, lineHeight: 1.6, color: 'var(--muted)' }}>
              One moment.
            </p>
          </>
        )}

        <div style={{ marginTop: 32 }}>
          <BuildString />
        </div>
      </div>
    </AuthShell>
  )
}
