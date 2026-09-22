import * as React from 'react'
import { Navigate, useNavigate } from 'react-router'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { qk } from '@/lib/queryKeys'
import { useSession } from '@/auth/SessionProvider'
import { useAccessCheck } from '@/auth/useAccessCheck'
import { AuthShell, BuildString, Wordmark } from '@/auth/AuthShell'
import { FullPageLoader } from '@/ui/full-page-loader'
import { persistLastWorkspace } from '@/shell/WorkspaceSwitcher'
import '@/styles/auth-theme.css'

/**
 * First run: an account that belongs to no workspace and can open no project.
 *
 * Until now that account landed on /no-access — correct for someone waiting on
 * an invitation, wrong for the first person through the door, who has nobody
 * to wait for. create_workspace() has existed since the first migration and
 * makes its caller the owner; nothing in the app ever called it, so the only
 * way to get a first workspace was to insert one by hand.
 *
 * /no-access still exists and is still right for the other case: you hold a
 * membership but nothing has been shared with you yet. The two are separated
 * by useAccessCheck().needsWorkspace — see the note there on why a stakeholder
 * with zero memberships must NOT be sent here.
 */

/** Same shape create_project_full derives for projects: lowercase, hyphenated. */
function slugify(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60)
}

export function CreateWorkspaceScreen() {
  const { session, user, isLoading, signOut } = useSession()
  const access = useAccessCheck()
  const navigate = useNavigate()
  const qc = useQueryClient()

  const [name, setName] = React.useState('')
  const [error, setError] = React.useState<string | null>(null)
  const nameRef = React.useRef<HTMLInputElement>(null)
  const errorRef = React.useRef<HTMLDivElement>(null)
  // Ref, not state: a double click fires twice before React re-renders, and
  // two workspaces from one intent is a mess to unpick.
  const inFlight = React.useRef(false)

  React.useEffect(() => { nameRef.current?.focus() }, [])
  React.useEffect(() => { if (error) errorRef.current?.focus() }, [error])

  const create = useMutation({
    mutationFn: async (workspaceName: string): Promise<string> => {
      const { data, error: rpcError } = await supabase.rpc('create_workspace', {
        p_name: workspaceName,
        p_slug: slugify(workspaceName) || 'workspace',
      })
      if (rpcError) throw rpcError
      return data as string
    },
  })

  if (isLoading) return <FullPageLoader label="Signing you in" />
  if (!session) return <Navigate to="/sign-in" replace />
  if (access.isLoading) return <FullPageLoader label="Signing you in" />
  // Already has somewhere to go — this screen is first-run only.
  if (access.data && !access.data.needsWorkspace) return <Navigate to="/dashboard" replace />

  const trimmed = name.trim()

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (inFlight.current) return
    if (!trimmed) {
      setError('Give your workspace a name.')
      nameRef.current?.focus()
      return
    }
    if (trimmed.length > 120) {
      setError('Max 120 characters.')
      nameRef.current?.focus()
      return
    }

    inFlight.current = true
    setError(null)
    create.mutate(trimmed, {
      onSuccess: async (workspaceId) => {
        persistLastWorkspace(workspaceId)
        // refetchType 'all', and awaited, for a specific reason. Both of these
        // queries are INACTIVE here — nothing on this screen subscribes to the
        // workspace list — and a plain invalidate only marks inactive queries
        // stale, so the await resolved instantly and we navigated with the
        // caches still saying this account had nowhere to go. The result was a
        // visible bounce: /dashboard read "no workspace", sent us back to
        // /welcome, which read the now-fresh data and sent us forward again.
        await Promise.all([
          qc.invalidateQueries({ queryKey: qk.workspaces(), refetchType: 'all' }),
          qc.invalidateQueries({ queryKey: ['access-check'], refetchType: 'all' }),
        ])
        navigate('/dashboard', { replace: true })
      },
      onError: (err) => {
        inFlight.current = false
        const code = (err as { code?: string } | null)?.code
        setError(
          code === '23505'
            ? 'A workspace with that name already exists. Try another.'
            : "Couldn't create the workspace. Check your connection and try again.",
        )
      },
    })
  }

  const busy = create.isPending

  return (
    <AuthShell>
      <div style={{ width: '100%', maxWidth: 408 }}>
        <div className="lg:hidden" style={{ marginBottom: 28 }}>
          <Wordmark />
        </div>

        <p className="auth-mono" style={{ margin: 0, fontSize: 11.5, letterSpacing: '0.14em', color: '#8A6420' }}>
          FIRST RUN
        </p>
        <h1 className="auth-display" style={{ fontSize: 'clamp(30px, 5vw, 36px)', lineHeight: 1.1, margin: '14px 0 0' }}>
          Name your workspace
        </h1>
        <p style={{ margin: '12px 0 0', fontSize: 15, lineHeight: 1.6, color: 'var(--muted)' }}>
          A workspace holds your projects, your team and your clients. Usually your company
          name. You can rename it later in Settings.
        </p>

        {error && (
          <div
            ref={errorRef}
            role="alert"
            tabIndex={-1}
            style={{
              marginTop: 20, background: 'var(--error-bg)', border: '1px solid var(--error-border)',
              borderRadius: 'var(--radius-field)', padding: '11px 13px', fontSize: 13.5,
              color: 'var(--error-text)', outline: 'none',
            }}
          >
            {error}
          </div>
        )}

        <form onSubmit={onSubmit} style={{ marginTop: 24 }}>
          <label
            htmlFor="ws-name"
            style={{ display: 'block', fontSize: 13.5, fontWeight: 500, color: 'var(--ink)', marginBottom: 7 }}
          >
            Workspace name
          </label>
          <input
            ref={nameRef}
            id="ws-name"
            className="auth-field"
            value={name}
            disabled={busy}
            maxLength={120}
            placeholder="e.g. Atkinson Studio"
            aria-invalid={error ? 'true' : undefined}
            aria-describedby="ws-name-help"
            onChange={(e) => { setName(e.target.value); if (error) setError(null) }}
          />
          <p id="ws-name-help" style={{ margin: '7px 0 0', fontSize: 12.5, color: 'var(--faint)' }}>
            You&apos;ll be its owner. {trimmed && <>URL: <span className="auth-mono">/{slugify(trimmed) || 'workspace'}</span></>}
          </p>

          <button
            type="submit"
            className="auth-btn-primary"
            style={{ marginTop: 22 }}
            disabled={!trimmed || busy}
            aria-busy={busy || undefined}
          >
            {busy ? 'Creating…' : 'Create workspace'}
          </button>
        </form>

        <p style={{ margin: '18px 0 0', fontSize: 13, color: 'var(--muted)' }}>
          Expecting an invitation instead?{' '}
          <button
            type="button"
            onClick={async () => { await signOut(); navigate('/sign-in', { replace: true }) }}
            className="auth-link"
            style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', font: 'inherit' }}
          >
            Sign out
          </button>
          {user?.email ? ` (${user.email})` : ''}
        </p>

        <div style={{ marginTop: 32 }}>
          <BuildString />
        </div>
      </div>
    </AuthShell>
  )
}
