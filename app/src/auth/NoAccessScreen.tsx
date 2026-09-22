import { Navigate, useNavigate } from 'react-router'
import { useSession } from '@/auth/SessionProvider'
import { useAccessCheck } from '@/auth/useAccessCheck'
import { AuthShell, BuildString, Wordmark } from '@/auth/AuthShell'
import '@/styles/auth-theme.css'

/**
 * Reached when someone signs in successfully but has nowhere to go: no
 * projects they can open, and no admin role anywhere. Landing them on an empty
 * workspace looks like the product is broken; this says what happened and who
 * can fix it.
 *
 * "Ask your project lead" only makes sense if there IS one. An account with no
 * workspace at all has nobody to ask, so it belongs on /welcome instead — this
 * guard catches anyone who reaches this URL directly.
 */
export function NoAccessScreen() {
  const { signOut } = useSession()
  const navigate = useNavigate()
  const access = useAccessCheck()

  if (access.data?.needsWorkspace) return <Navigate to="/welcome" replace />

  return (
    <AuthShell>
      <div style={{ width: '100%', maxWidth: 408 }}>
        <div className="lg:hidden" style={{ marginBottom: 28 }}>
          <Wordmark />
        </div>

        <h1 className="auth-display" style={{ fontSize: 'clamp(30px, 5vw, 36px)', lineHeight: 1.1, margin: 0 }}>
          No access yet
        </h1>
        <p style={{ margin: '12px 0 0', fontSize: 15, lineHeight: 1.6, color: 'var(--muted)' }}>
          You&apos;re signed in, but you haven&apos;t been added to a workspace or project yet. Ask
          your project lead to invite you.
        </p>

        <button
          type="button"
          className="auth-btn-primary"
          style={{ marginTop: 24 }}
          onClick={async () => {
            await signOut()
            navigate('/sign-in', { replace: true })
          }}
        >
          Sign out
        </button>

        <div style={{ marginTop: 32 }}>
          <BuildString />
        </div>
      </div>
    </AuthShell>
  )
}
