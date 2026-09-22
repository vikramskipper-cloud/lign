import * as React from 'react'
import '@/styles/auth-theme.css'

/**
 * Two-column auth chrome: fixed brand panel ≥1024px, single column below.
 *
 * The panel is decorative. It is hidden outright on mobile rather than
 * stacked, because a marketing column above a login form pushes the one thing
 * the user came for below the fold.
 */

export function Wordmark() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <div
        aria-hidden="true"
        style={{
          width: 32,
          height: 32,
          borderRadius: 7,
          background: 'var(--ink)',
          display: 'grid',
          placeItems: 'center',
          flex: '0 0 32px',
        }}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
          <path
            d="M4 2.5v9h6"
            fill="none"
            stroke="#F3EEE7"
            strokeWidth="1.9"
            strokeLinecap="square"
          />
        </svg>
      </div>
      <span
        style={{
          fontFamily: 'var(--font-ui)',
          fontWeight: 600,
          fontSize: 15,
          letterSpacing: '0.18em',
          color: 'var(--ink)',
        }}
      >
        LIGN
      </span>
    </div>
  )
}

export function BuildString() {
  // Injected by vite.config.ts. Empty means no meaningful build id, in which
  // case the suffix is dropped rather than printed as "BUILD undefined".
  const version = typeof __APP_VERSION__ === 'string' ? __APP_VERSION__ : ''
  return (
    <p
      className="auth-mono"
      style={{ margin: 0, fontSize: 11, letterSpacing: '0.1em', color: 'var(--faint)' }}
    >
      CLOSED BETA{version ? ` · BUILD ${version}` : ''}
    </p>
  )
}

const REVISIONS = [
  { id: 'DSN · R3', title: 'Elevation set — East facade', label: 'Approved', dot: 'var(--status-approved)', text: 'var(--status-approved-text)', dim: false },
  { id: 'DSN · R2', title: 'Elevation set — East facade', label: 'Changes requested', dot: 'var(--status-changes)', text: 'var(--status-changes-text)', dim: false },
  { id: 'DSN · R1', title: 'Elevation set — East facade', label: 'Superseded', dot: 'var(--status-superseded)', text: 'var(--status-superseded-text)', dim: true },
]

function BrandPanel() {
  return (
    <aside
      className="auth-brand-panel"
      style={{
        width: 576,
        flex: '0 0 576px',
        background: 'var(--panel)',
        borderRight: '1px solid var(--panel-border)',
        padding: '40px 56px',
      }}
    >
      <Wordmark />

      <div style={{ maxWidth: 440 }}>
        <p
          className="auth-mono"
          style={{ margin: 0, fontSize: 11.5, letterSpacing: '0.14em', color: '#8A6420' }}
        >
          THE PROJECT RECORD
        </p>
        <h2
          className="auth-display"
          style={{ margin: '18px 0 0', fontSize: 52, lineHeight: 1.08 }}
        >
          Every decision on the project, on one record.
        </h2>
        <p style={{ margin: '18px 0 0', fontSize: 16, lineHeight: 1.55, color: 'var(--muted)' }}>
          Versions, comments and sign-offs, kept in one place and time-stamped.
        </p>

        {/* Illustrative only — not real data, so it is hidden from assistive tech. */}
        <div aria-hidden="true" style={{ marginTop: 30, display: 'grid', gap: 8 }}>
          {REVISIONS.map((r) => (
            <div
              key={r.id}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 14,
                background: 'var(--surface)',
                border: '1px solid var(--border-soft)',
                borderRadius: 'var(--radius-card)',
                padding: '11px 14px',
                opacity: r.dim ? 0.62 : 1,
              }}
            >
              <span
                className="auth-mono"
                style={{ fontSize: 11.5, color: 'var(--faint)', flex: '0 0 62px' }}
              >
                {r.id}
              </span>
              <span style={{ fontSize: 13.5, color: 'var(--text)', flex: 1, minWidth: 0 }}>
                {r.title}
              </span>
              <span style={{ display: 'flex', alignItems: 'center', gap: 6, flex: '0 0 auto' }}>
                <span
                  style={{ width: 7, height: 7, borderRadius: '50%', background: r.dot, display: 'block' }}
                />
                <span style={{ fontSize: 12, color: r.text, whiteSpace: 'nowrap' }}>{r.label}</span>
              </span>
            </div>
          ))}
        </div>
      </div>

      <BuildString />
    </aside>
  )
}

export function AuthShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="auth-theme" style={{ display: 'flex', minHeight: '100dvh' }}>
      <BrandPanel />
      <main
        style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: 24,
          minWidth: 0,
        }}
      >
        {children}
      </main>
    </div>
  )
}
