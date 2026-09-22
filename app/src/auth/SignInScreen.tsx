import * as React from 'react'
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import { setSessionPersistence } from '@/lib/sessionPersistence'
import { resolveRedirect } from '@/auth/redirect'
import { FullPageLoader } from '@/ui/full-page-loader'
import { AuthShell, BuildString, Wordmark } from '@/auth/AuthShell'
import '@/styles/auth-theme.css'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/** Where "request access" points. Placeholder until there is a real destination. */
const REQUEST_ACCESS_HREF = '#'

type FieldError = 'email' | 'password' | null

/**
 * Maps provider errors to copy a person can act on.
 *
 * Two rules: never surface a raw provider string, and never reveal whether an
 * account exists. Supabase returns the same `invalid_credentials` for an
 * unknown email and a wrong password, and that property is worth preserving —
 * distinguishing them would hand an attacker a user-enumeration oracle.
 */
function messageFor(error: unknown): string {
  const e = error as { message?: string; status?: number; code?: string } | null
  const status = e?.status
  const code = (e?.code ?? '').toLowerCase()
  const raw = (e?.message ?? '').toLowerCase()

  if (status === 429 || code === 'over_request_rate_limit' || raw.includes('rate limit')) {
    return 'Too many attempts. Wait a few minutes and try again.'
  }
  if (
    status === 400 ||
    code === 'invalid_credentials' ||
    raw.includes('invalid login') ||
    raw.includes('invalid credentials')
  ) {
    return "That email and password don't match."
  }
  if (raw.includes('failed to fetch') || raw.includes('networkerror') || status === 0 || !status) {
    return "Couldn't reach Lign. Check your connection and try again."
  }
  return "Couldn't reach Lign. Check your connection and try again."
}

export function SignInScreen() {
  const { session, isLoading } = useSession()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()

  const [email, setEmail] = React.useState('')
  const [password, setPassword] = React.useState('')
  const [keepSignedIn, setKeepSignedIn] = React.useState(true)
  const [showPassword, setShowPassword] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)
  const [invalidField, setInvalidField] = React.useState<FieldError>(null)
  const [submitting, setSubmitting] = React.useState(false)

  const emailRef = React.useRef<HTMLInputElement>(null)
  const passwordRef = React.useRef<HTMLInputElement>(null)
  const errorRef = React.useRef<HTMLDivElement>(null)
  // Ref, not state: a double click can fire twice before React re-renders.
  const inFlight = React.useRef(false)

  const redirectTo = resolveRedirect(searchParams)

  React.useEffect(() => {
    if (error) errorRef.current?.focus()
  }, [error])

  if (isLoading) return <FullPageLoader />
  // A signed-in visitor never sees this page.
  if (session) return <Navigate to={redirectTo} replace />

  const fail = (message: string, field: FieldError) => {
    setError(message)
    setInvalidField(field)
    if (field === 'email') emailRef.current?.focus()
    if (field === 'password') passwordRef.current?.focus()
  }

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (inFlight.current) return

    const trimmed = email.trim()
    setError(null)
    setInvalidField(null)

    // Client validation — no request leaves the browser if this fails.
    if (!trimmed) return fail('Enter your work email.', 'email')
    if (!EMAIL_RE.test(trimmed)) return fail('Enter a valid email address.', 'email')
    if (!password) return fail('Enter your password.', 'password')

    inFlight.current = true
    setSubmitting(true)

    // Must precede sign-in so the session is written to the chosen store
    // rather than moved afterwards.
    setSessionPersistence(keepSignedIn)

    try {
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: trimmed,
        password,
      })
      if (signInError) {
        setPassword('') // keep the email, drop the secret
        setError(messageFor(signInError))
        setInvalidField(null)
        return
      }
      navigate(redirectTo, { replace: true })
    } catch (err) {
      setPassword('')
      setError(messageFor(err))
    } finally {
      inFlight.current = false
      setSubmitting(false)
    }
  }

  const describedBy = (field: 'email' | 'password') =>
    invalidField === field ? 'signin-error' : undefined

  return (
    <AuthShell>
      <form
        onSubmit={onSubmit}
        aria-busy={submitting}
        noValidate
        style={{ width: '100%', maxWidth: 408 }}
      >
        <div className="lg:hidden" style={{ marginBottom: 28 }}>
          <Wordmark />
        </div>

        <h1
          className="auth-display"
          style={{ fontSize: 'clamp(34px, 5vw, 36px)', lineHeight: 1.1, margin: 0 }}
        >
          Sign in
        </h1>
        <p style={{ margin: '8px 0 0', fontSize: 14.5, color: 'var(--muted)' }}>
          Use the work email your account was created with.
        </p>

        {error && (
          <div
            id="signin-error"
            ref={errorRef}
            role="alert"
            tabIndex={-1}
            style={{
              display: 'flex',
              gap: 9,
              alignItems: 'flex-start',
              marginTop: 20,
              padding: '11px 13px',
              background: 'var(--error-bg)',
              border: '1px solid var(--error-border)',
              borderRadius: 'var(--radius-field)',
              color: 'var(--error-text)',
              fontSize: 14,
              lineHeight: 1.45,
            }}
          >
            <svg
              width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"
              style={{ flex: '0 0 16px', marginTop: 1, fill: 'var(--error-icon)' }}
            >
              <path d="M8 1.5 15 14H1L8 1.5Zm0 4.2a.8.8 0 0 0-.8.8v2.6a.8.8 0 0 0 1.6 0V6.5a.8.8 0 0 0-.8-.8Zm0 5.1a.95.95 0 1 0 0 1.9.95.95 0 0 0 0-1.9Z" />
            </svg>
            <span>{error}</span>
          </div>
        )}

        <div style={{ marginTop: 22 }}>
          <label
            htmlFor="signin-email"
            style={{ display: 'block', fontSize: 13.5, fontWeight: 500, color: 'var(--ink)', marginBottom: 6 }}
          >
            Work email
          </label>
          <input
            id="signin-email"
            ref={emailRef}
            className="auth-field"
            type="email"
            name="email"
            autoComplete="username"
            placeholder="you@studio.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={submitting}
            aria-invalid={invalidField === 'email' || undefined}
            aria-describedby={describedBy('email')}
            autoFocus
          />
        </div>

        <div style={{ marginTop: 16 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 6 }}>
            <label htmlFor="signin-password" style={{ fontSize: 13.5, fontWeight: 500, color: 'var(--ink)' }}>
              Password
            </label>
            <Link to="/reset-password" className="auth-link" style={{ fontSize: 13 }}>
              Forgot password?
            </Link>
          </div>
          <div style={{ position: 'relative' }}>
            <input
              id="signin-password"
              ref={passwordRef}
              className="auth-field"
              type={showPassword ? 'text' : 'password'}
              name="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              disabled={submitting}
              aria-invalid={invalidField === 'password' || undefined}
              aria-describedby={describedBy('password')}
              style={{ paddingRight: 62 }}
            />
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              disabled={submitting}
              aria-pressed={showPassword}
              aria-controls="signin-password"
              style={{
                position: 'absolute',
                right: 6,
                top: '50%',
                transform: 'translateY(-50%)',
                height: 32,
                padding: '0 8px',
                background: 'transparent',
                border: 'none',
                color: 'var(--muted)',
                fontSize: 13,
                fontFamily: 'var(--font-ui)',
                cursor: submitting ? 'not-allowed' : 'pointer',
                borderRadius: 5,
              }}
            >
              {showPassword ? 'Hide' : 'Show'}
            </button>
          </div>
        </div>

        <label
          style={{ display: 'flex', alignItems: 'center', gap: 9, marginTop: 16, fontSize: 14, color: 'var(--text)', cursor: 'pointer' }}
        >
          <input
            type="checkbox"
            className="auth-check"
            checked={keepSignedIn}
            onChange={(e) => setKeepSignedIn(e.target.checked)}
            disabled={submitting}
          />
          Keep me signed in on this device
        </label>

        <button type="submit" className="auth-btn-primary" disabled={submitting} style={{ marginTop: 20 }}>
          {submitting ? 'Signing in…' : 'Sign in'}
        </button>

        <p style={{ margin: '18px 0 0', fontSize: 13, lineHeight: 1.55, color: 'var(--muted)' }}>
          Access is invite-only during the beta. Clients are added to a project by its lead —{' '}
          <a className="auth-link" href={REQUEST_ACCESS_HREF}>
            request access
          </a>
          .
        </p>

        <div className="lg:hidden" style={{ marginTop: 32 }}>
          <BuildString />
        </div>
      </form>
    </AuthShell>
  )
}
