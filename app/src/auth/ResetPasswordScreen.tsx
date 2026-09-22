import * as React from 'react'
import { Link } from 'react-router'
import { supabase } from '@/lib/supabase'
import { AuthShell, BuildString, Wordmark } from '@/auth/AuthShell'
import '@/styles/auth-theme.css'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/**
 * Password reset request.
 *
 * The confirmation is deliberately identical whether or not an account exists,
 * and is shown even when Supabase returns an error — anything else turns this
 * form into an account-enumeration oracle, which matters more here than
 * telling the user their address was unrecognised.
 *
 * The one exception is rate limiting, where staying silent would leave someone
 * waiting for a mail that was never sent.
 */
export function ResetPasswordScreen() {
  const [email, setEmail] = React.useState('')
  const [sent, setSent] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)
  const [invalid, setInvalid] = React.useState(false)
  const [submitting, setSubmitting] = React.useState(false)
  const inFlight = React.useRef(false)
  const emailRef = React.useRef<HTMLInputElement>(null)
  const alertRef = React.useRef<HTMLDivElement>(null)

  React.useEffect(() => {
    if (error) alertRef.current?.focus()
  }, [error])

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (inFlight.current) return
    const trimmed = email.trim()
    setError(null)
    setInvalid(false)

    if (!trimmed || !EMAIL_RE.test(trimmed)) {
      setInvalid(true)
      setError('Enter a valid email address.')
      emailRef.current?.focus()
      return
    }

    inFlight.current = true
    setSubmitting(true)
    try {
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(trimmed, {
        redirectTo: `${window.location.origin}/sign-in`,
      })
      if (resetError && (resetError.status === 429 || /rate limit/i.test(resetError.message))) {
        setError('Too many attempts. Wait a few minutes and try again.')
        return
      }
      // Any other outcome, success or failure, gets the same answer.
      setSent(true)
    } catch {
      setSent(true)
    } finally {
      inFlight.current = false
      setSubmitting(false)
    }
  }

  return (
    <AuthShell>
      <div style={{ width: '100%', maxWidth: 408 }}>
        <div className="lg:hidden" style={{ marginBottom: 28 }}>
          <Wordmark />
        </div>

        <h1 className="auth-display" style={{ fontSize: 'clamp(30px, 5vw, 36px)', lineHeight: 1.1, margin: 0 }}>
          Reset password
        </h1>

        {sent ? (
          <>
            <p
              role="status"
              style={{ margin: '12px 0 0', fontSize: 15, lineHeight: 1.6, color: 'var(--muted)' }}
            >
              If an account exists for that email, we&apos;ve sent a reset link.
            </p>
            <p style={{ margin: '20px 0 0', fontSize: 13.5 }}>
              <Link to="/sign-in" className="auth-link">
                Back to sign in
              </Link>
            </p>
          </>
        ) : (
          <form onSubmit={onSubmit} aria-busy={submitting} noValidate>
            <p style={{ margin: '8px 0 0', fontSize: 14.5, color: 'var(--muted)' }}>
              We&apos;ll email you a link to set a new password.
            </p>

            {error && (
              <div
                id="reset-error"
                ref={alertRef}
                role="alert"
                tabIndex={-1}
                style={{
                  marginTop: 20,
                  padding: '11px 13px',
                  background: 'var(--error-bg)',
                  border: '1px solid var(--error-border)',
                  borderRadius: 'var(--radius-field)',
                  color: 'var(--error-text)',
                  fontSize: 14,
                }}
              >
                {error}
              </div>
            )}

            <div style={{ marginTop: 22 }}>
              <label
                htmlFor="reset-email"
                style={{ display: 'block', fontSize: 13.5, fontWeight: 500, color: 'var(--ink)', marginBottom: 6 }}
              >
                Work email
              </label>
              <input
                id="reset-email"
                ref={emailRef}
                className="auth-field"
                type="email"
                name="email"
                autoComplete="username"
                placeholder="you@studio.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={submitting}
                aria-invalid={invalid || undefined}
                aria-describedby={invalid ? 'reset-error' : undefined}
                autoFocus
              />
            </div>

            <button type="submit" className="auth-btn-primary" disabled={submitting} style={{ marginTop: 20 }}>
              {submitting ? 'Sending…' : 'Send reset link'}
            </button>

            <p style={{ margin: '18px 0 0', fontSize: 13.5 }}>
              <Link to="/sign-in" className="auth-link">
                Back to sign in
              </Link>
            </p>
          </form>
        )}

        <div style={{ marginTop: 32 }}>
          <BuildString />
        </div>
      </div>
    </AuthShell>
  )
}
