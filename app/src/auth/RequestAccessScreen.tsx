import * as React from 'react'
import { Link } from 'react-router'
import { toast } from 'sonner'
import { AuthShell, BuildString, Wordmark } from '@/auth/AuthShell'
import {
  AccessRequestInvalid,
  EMAIL_RE,
  TEAM_SIZES,
  useSubmitAccessRequest,
  type TeamSize,
} from '@/features/access/accessRequests'
import '@/styles/auth-theme.css'

/**
 * APP 020. The destination for the "request access" link the sign-in page has
 * carried since it was written, pointing at href="#".
 *
 * Public and unauthenticated — it is outside the auth gate, and the RPC behind
 * it is granted to `anon`. It is NOT a sign-up form: nothing here creates an
 * account or a session. LIGN staff review the application; an approved applicant
 * receives a welcome email to set their password and activate their organisation.
 *
 * Submitting always appears to succeed for a well-formed application, even for
 * an address that has already applied. That is the server's behaviour and this
 * screen must not undermine it — "you have already requested access" would
 * tell any stranger whether an address is known to us.
 */

const LABEL: React.CSSProperties = {
  display: 'block',
  fontSize: 13.5,
  fontWeight: 500,
  color: 'var(--ink)',
  marginBottom: 6,
}

const HINT: React.CSSProperties = { margin: '6px 0 0', fontSize: 12.5, color: 'var(--faint)' }

/** Native select, dressed as an .auth-field with a caret of our own. */
const SELECT_STYLE: React.CSSProperties = {
  appearance: 'none',
  WebkitAppearance: 'none',
  backgroundImage:
    "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'><path d='M1 1.5 6 6.5l5-5' fill='none' stroke='%238A8079' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/></svg>\")",
  backgroundRepeat: 'no-repeat',
  backgroundPosition: 'right 13px center',
  paddingRight: 34,
}

const TEAM_SIZE_LABEL: Record<TeamSize, string> = {
  '1': 'Just me',
  '2-5': '2–5 people',
  '6-20': '6–20 people',
  '21-50': '21–50 people',
  '51-200': '51–200 people',
  '200+': 'More than 200',
}

type Field = 'name' | 'email' | 'phone' | 'company' | 'companyRole' | 'teamSize'

export function RequestAccessScreen() {
  const submit = useSubmitAccessRequest()

  const [name, setName] = React.useState('')
  const [email, setEmail] = React.useState('')
  const [phone, setPhone] = React.useState('')
  const [company, setCompany] = React.useState('')
  const [companyRole, setCompanyRole] = React.useState('')
  const [teamSize, setTeamSize] = React.useState<TeamSize | ''>('')

  const [error, setError] = React.useState<string | null>(null)
  const [invalidField, setInvalidField] = React.useState<Field | null>(null)
  const [done, setDone] = React.useState<string | null>(null)

  const nameRef = React.useRef<HTMLInputElement>(null)
  const emailRef = React.useRef<HTMLInputElement>(null)
  const phoneRef = React.useRef<HTMLInputElement>(null)
  const companyRef = React.useRef<HTMLInputElement>(null)
  const roleRef = React.useRef<HTMLInputElement>(null)
  const sizeRef = React.useRef<HTMLSelectElement>(null)
  const errorRef = React.useRef<HTMLDivElement>(null)
  const doneRef = React.useRef<HTMLHeadingElement>(null)
  // Ref, not state: a double click fires twice before React re-renders, and on
  // a first submit that would be two applications from one intent.
  const inFlight = React.useRef(false)

  React.useEffect(() => {
    if (error) errorRef.current?.focus()
  }, [error])
  React.useEffect(() => {
    if (done) doneRef.current?.focus()
  }, [done])

  const focusField = (field: Field) => {
    const map: Record<Field, React.RefObject<HTMLElement | null>> = {
      name: nameRef,
      email: emailRef,
      phone: phoneRef,
      company: companyRef,
      companyRole: roleRef,
      teamSize: sizeRef,
    }
    map[field].current?.focus()
  }

  const fail = (field: Field, message: string) => {
    setInvalidField(field)
    setError(message)
    focusField(field)
  }

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (inFlight.current) return

    // The same rules the server enforces, checked here only so the common
    // mistakes never make a round trip. The server remains the authority.
    if (!name.trim()) return fail('name', 'Tell us your name.')
    if (name.trim().length > 120) return fail('name', 'Name is too long (120 characters max).')
    if (!EMAIL_RE.test(email.trim())) return fail('email', 'Enter a valid work email address.')
    if (email.trim().length > 254) return fail('email', 'That email address is too long.')
    if (!company.trim()) return fail('company', 'Tell us your company name.')
    if (company.trim().length > 120) return fail('company', 'Company name is too long (120 characters max).')
    if (!phone.trim()) return fail('phone', 'Enter your phone number.')
    if (!companyRole.trim()) return fail('companyRole', 'What is your role?')
    if (companyRole.trim().length > 120) return fail('companyRole', 'Role is too long (120 characters max).')
    if (phone.trim().length > 40) return fail('phone', 'That phone number is too long.')
    if (!teamSize) return fail('teamSize', 'Pick a team size.')

    inFlight.current = true
    setError(null)
    setInvalidField(null)

    submit.mutate(
      { name, email, phone, company, companyRole, teamSize },
      {
        onSuccess: () => {
          const addressed = email.trim().toLowerCase()
          toast.success('Request sent')
          setDone(addressed)
        },
        onError: (err) => {
          inFlight.current = false
          if (err instanceof AccessRequestInvalid) {
            setError(err.message)
            errorRef.current?.focus()
            return
          }
          setError("Couldn't send your request. Check your connection and try again.")
        },
      },
    )
  }

  const busy = submit.isPending

  if (done) {
    return (
      <AuthShell>
        <div style={{ width: '100%', maxWidth: 408 }}>
          <div className="lg:hidden" style={{ marginBottom: 28 }}>
            <Wordmark />
          </div>

          <p
            className="auth-mono"
            style={{ margin: 0, fontSize: 11.5, letterSpacing: '0.14em', color: '#2E6B4C' }}
          >
            REQUEST RECEIVED
          </p>
          <h1
            ref={doneRef}
            tabIndex={-1}
            className="auth-display"
            style={{ fontSize: 'clamp(30px, 5vw, 36px)', lineHeight: 1.1, margin: '14px 0 0', outline: 'none' }}
          >
            Thanks — we have it
          </h1>
          <p style={{ margin: '12px 0 0', fontSize: 15, lineHeight: 1.6, color: 'var(--muted)' }}>
            We review every request by hand during the beta. We&apos;ll email{' '}
            <strong style={{ color: 'var(--ink)', fontWeight: 500 }}>{done}</strong> with a secure link to set your password if your
            request is approved — there&apos;s nothing to do in the meantime.
          </p>

          <p style={{ margin: '26px 0 0', fontSize: 13, color: 'var(--muted)' }}>
            Already have an account?{' '}
            <Link to="/sign-in" className="auth-link">
              Sign in
            </Link>
          </p>

          <div style={{ marginTop: 32 }}>
            <BuildString />
          </div>
        </div>
      </AuthShell>
    )
  }

  const describedBy = (field: Field) => (invalidField === field ? 'request-error' : undefined)

  return (
    <AuthShell>
      <form onSubmit={onSubmit} aria-busy={busy} noValidate style={{ width: '100%', maxWidth: 408 }}>
        <div className="lg:hidden" style={{ marginBottom: 28 }}>
          <Wordmark />
        </div>

        <p
          className="auth-mono"
          style={{ margin: 0, fontSize: 11.5, letterSpacing: '0.14em', color: '#8A6420' }}
        >
          INVITE-ONLY BETA
        </p>
        <h1
          className="auth-display"
          style={{ fontSize: 'clamp(30px, 5vw, 36px)', lineHeight: 1.1, margin: '14px 0 0' }}
        >
          Request access
        </h1>
        <p style={{ margin: '10px 0 0', fontSize: 14.5, lineHeight: 1.6, color: 'var(--muted)' }}>
          We&apos;re onboarding studios a few at a time. Tell us a little about your team and
          we&apos;ll be in touch by email.
        </p>

        {error && (
          <div
            id="request-error"
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
              outline: 'none',
            }}
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 16 16"
              aria-hidden="true"
              style={{ flex: '0 0 16px', marginTop: 1, fill: 'var(--error-icon)' }}
            >
              <path d="M8 1.5 15 14H1L8 1.5Zm0 4.2a.8.8 0 0 0-.8.8v2.6a.8.8 0 0 0 1.6 0V6.5a.8.8 0 0 0-.8-.8Zm0 5.1a.95.95 0 1 0 0 1.9.95.95 0 0 0 0-1.9Z" />
            </svg>
            <span>{error}</span>
          </div>
        )}

        <div style={{ marginTop: 22 }}>
          <label htmlFor="ra-name" style={LABEL}>
            Full name
          </label>
          <input
            id="ra-name"
            ref={nameRef}
            className="auth-field"
            autoComplete="name"
            maxLength={120}
            placeholder="Ada Patel"
            value={name}
            disabled={busy}
            aria-invalid={invalidField === 'name' || undefined}
            aria-describedby={describedBy('name')}
            onChange={(e) => {
              setName(e.target.value)
              if (error) setError(null)
            }}
            autoFocus
          />
        </div>

        <div style={{ marginTop: 16 }}>
          <label htmlFor="ra-email" style={LABEL}>
            Work email
          </label>
          <input
            id="ra-email"
            ref={emailRef}
            className="auth-field"
            type="email"
            autoComplete="email"
            maxLength={254}
            placeholder="you@studio.com"
            value={email}
            disabled={busy}
            aria-invalid={invalidField === 'email' || undefined}
            aria-describedby={describedBy('email')}
            onChange={(e) => {
              setEmail(e.target.value)
              if (error) setError(null)
            }}
          />
        </div>

        <div style={{ marginTop: 16 }}>
          <label htmlFor="ra-phone" style={LABEL}>
            Phone
          </label>
          <input
            id="ra-phone"
            ref={phoneRef}
            className="auth-field"
            type="tel"
            autoComplete="tel"
            maxLength={40}
            placeholder="+44 7700 900000"
            value={phone}
            disabled={busy}
            aria-invalid={invalidField === 'phone' || undefined}
            aria-describedby={describedBy('phone')}
            onChange={(e) => {
              setPhone(e.target.value)
              if (error) setError(null)
            }}
          />
        </div>

        <div style={{ marginTop: 16 }}>
          <label htmlFor="ra-company" style={LABEL}>Company</label>
          <input
            id="ra-company"
            ref={companyRef}
            className="auth-field"
            autoComplete="organization"
            maxLength={120}
            placeholder="Your company name"
            value={company}
            disabled={busy}
            aria-invalid={invalidField === 'company' || undefined}
            aria-describedby={describedBy('company')}
            onChange={(e) => {
              setCompany(e.target.value)
              if (error) setError(null)
            }}
          />
        </div>

        <div style={{ marginTop: 16 }}>
          <label htmlFor="ra-role" style={LABEL}>
            Your role
          </label>
          <input
            id="ra-role"
            ref={roleRef}
            className="auth-field"
            autoComplete="organization-title"
            maxLength={120}
            placeholder="Principal, Design Lead, Founder…"
            value={companyRole}
            disabled={busy}
            aria-invalid={invalidField === 'companyRole' || undefined}
            aria-describedby={describedBy('companyRole')}
            onChange={(e) => {
              setCompanyRole(e.target.value)
              if (error) setError(null)
            }}
          />
        </div>

        <div style={{ marginTop: 16 }}>
          <label htmlFor="ra-size" style={LABEL}>
            Team size
          </label>
          <select
            id="ra-size"
            ref={sizeRef}
            className="auth-field"
            style={SELECT_STYLE}
            value={teamSize}
            disabled={busy}
            aria-invalid={invalidField === 'teamSize' || undefined}
            aria-describedby={describedBy('teamSize')}
            onChange={(e) => {
              setTeamSize(e.target.value as TeamSize)
              if (error) setError(null)
            }}
          >
            <option value="" disabled>
              Select…
            </option>
            {TEAM_SIZES.map((s) => (
              <option key={s} value={s}>
                {TEAM_SIZE_LABEL[s]}
              </option>
            ))}
          </select>
          <p style={HINT}>How many people would be working in LIGN.</p>
        </div>

        <button
          type="submit"
          className="auth-btn-primary"
          style={{ marginTop: 24 }}
          disabled={busy}
          aria-busy={busy || undefined}
        >
          {busy ? 'Sending…' : 'Request access'}
        </button>

        <p style={{ margin: '18px 0 0', fontSize: 13, lineHeight: 1.55, color: 'var(--muted)' }}>
          Already have an account?{' '}
          <Link to="/sign-in" className="auth-link">
            Sign in
          </Link>
          . If a project lead has already invited you, use the link in your invitation instead.
        </p>

        <div className="lg:hidden" style={{ marginTop: 32 }}>
          <BuildString />
        </div>
      </form>
    </AuthShell>
  )
}
