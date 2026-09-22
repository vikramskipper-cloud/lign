import '@/styles/auth-theme.css'

/**
 * Full-viewport loading surface on the warm palette.
 *
 * Every state between "signed in" and "a screen is on the glass" has to look
 * like the same continuous page, or the transition reads as a flash. The zinc
 * `LoadingPage` cannot do that job here: it inherits the app palette and is
 * `min-h-[240px]`, so it paints as a small grey block on whatever surface
 * happens to be behind it — which during sign-in is the warm auth page and
 * during a redirect is the dashboard chrome.
 *
 * Deliberately no spinner for the first 250ms: a loader that appears and
 * vanishes inside a quarter second is itself the glitch. On a warm connection
 * the page simply renders.
 */
export function FullPageLoader({ label = 'Loading…' }: { label?: string }) {
  return (
    <div
      className="lign-warm"
      role="status"
      aria-live="polite"
      style={{
        minHeight: '100dvh',
        display: 'grid',
        placeItems: 'center',
        background: 'var(--bg)',
      }}
    >
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 12,
          opacity: 0,
          animation: 'lign-loader-in 200ms ease 250ms forwards',
        }}
      >
        <span
          aria-hidden="true"
          style={{
            width: 18,
            height: 18,
            borderRadius: '50%',
            border: '2px solid var(--border)',
            borderTopColor: 'var(--accent)',
            animation: 'lign-spin 700ms linear infinite',
          }}
        />
        <span className="auth-mono" style={{ fontSize: 11, letterSpacing: '0.1em', color: 'var(--faint)' }}>
          {label.toUpperCase()}
        </span>
      </div>
    </div>
  )
}
