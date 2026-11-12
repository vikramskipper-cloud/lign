import * as React from 'react'
import { Link, useNavigate } from 'react-router'
import { supabase } from '@/lib/supabase'
import { queryClient } from '@/lib/queryClient'
import { AuthShell, Wordmark } from '@/auth/AuthShell'
import { readActivationLink } from '@/auth/activation'
import '@/styles/auth-theme.css'

export function SetPasswordScreen() {
  const navigate = useNavigate()
  const [link] = React.useState(() => readActivationLink(window.location.hash))
  const [ready, setReady] = React.useState(false)
  const [password, setPassword] = React.useState('')
  const [confirmation, setConfirmation] = React.useState('')
  const [error, setError] = React.useState<string | null>(null)
  const [busy, setBusy] = React.useState(false)
  const [done, setDone] = React.useState(false)
  const inFlight = React.useRef(false)
  const verification = React.useRef<Promise<boolean> | null>(null)

  React.useEffect(() => {
    // One promise survives StrictMode's effect replay: links are single-use.
    verification.current ??= (async () => {
      if (new URLSearchParams(window.location.hash.slice(1)).has('error')) {
        window.history.replaceState(null, '', window.location.pathname)
        return false
      }
      if (link) {
        const { error } = await supabase.auth.verifyOtp({ token_hash: link.tokenHash, type: link.type })
        window.history.replaceState(null, '', window.location.pathname)
        return !error
      }
      // Supabase's standard recovery email verifies at /auth/v1/verify and
      // redirects here with an implicit session. getSession waits for it.
      const { data } = await supabase.auth.getSession()
      return Boolean(data.session)
    })()
    let active = true
    void verification.current.then((valid) => {
      if (!active) return
      setReady(valid)
      if (!valid) setError('This link has expired or has already been used. Request a new password link below.')
    }).catch(() => {
      if (active) setError('Could not verify this link. Check your connection and open the email link again.')
    })
    return () => { active = false }
  }, [link])

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!ready || inFlight.current) return
    if (password.length < 8) return setError('Use at least 8 characters for your password.')
    if (password !== confirmation) return setError('The passwords do not match.')
    inFlight.current = true
    setBusy(true)
    setError(null)
    try {
      const { error: passwordError } = await supabase.auth.updateUser({ password })
      // Retrying activation after a network failure may submit the same password.
      if (passwordError && passwordError.code !== 'same_password') throw passwordError
      const { error: activationError } = await supabase.rpc('complete_approved_access')
      if (activationError) throw activationError
      // Require the normal sign-in step after setting the password.
      await supabase.auth.signOut()
      queryClient.clear()
      setPassword('')
      setConfirmation('')
      setDone(true)
    } catch {
      setError('Could not finish setting up your access. Try again. If this continues, contact LIGN.')
    } finally {
      inFlight.current = false
      setBusy(false)
    }
  }

  return (
    <AuthShell>
      <div style={{ width: '100%', maxWidth: 408 }}>
        <div className="lg:hidden" style={{ marginBottom: 28 }}><Wordmark /></div>
        <h1 className="auth-display" style={{ fontSize: 34, margin: 0 }}>
          {done ? 'Your access is ready' : 'Set your password'}
        </h1>
        {done ? (
          <>
            <p role="status" style={{ marginTop: 16, color: 'var(--muted)' }}>Your password is set. Sign in to access LIGN.</p>
            <button className="auth-btn-primary" style={{ marginTop: 20 }} onClick={() => navigate(`/sign-in?returnTo=${encodeURIComponent(link?.returnTo ?? '/dashboard')}`, { replace: true })}>Continue to sign in</button>
          </>
        ) : (
          <form onSubmit={submit} aria-busy={busy}>
            <p style={{ color: 'var(--muted)', marginTop: 12 }}>Choose a password of at least 8 characters to access LIGN.</p>
            {error && <p role="alert" id="password-error" style={{ color: 'var(--error-text)' }}>{error}</p>}
            {!ready && !error && <p role="status">Verifying your secure link…</p>}
            {ready && (
              <>
                <label htmlFor="new-password" style={{ display: 'block', marginTop: 20, marginBottom: 6 }}>New password</label>
                <input id="new-password" className="auth-field" type="password" autoComplete="new-password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} disabled={busy} aria-describedby={error ? 'password-error' : undefined} />
                <label htmlFor="confirm-password" style={{ display: 'block', marginTop: 16, marginBottom: 6 }}>Confirm password</label>
                <input id="confirm-password" className="auth-field" type="password" autoComplete="new-password" required minLength={8} value={confirmation} onChange={(e) => setConfirmation(e.target.value)} disabled={busy} />
                <button className="auth-btn-primary" type="submit" style={{ marginTop: 24 }} disabled={busy}>{busy ? 'Setting up…' : 'Set password'}</button>
              </>
            )}
            <p style={{ marginTop: 20 }}><Link className="auth-link" to="/reset-password">Request a new password link</Link></p>
          </form>
        )}
      </div>
    </AuthShell>
  )
}
