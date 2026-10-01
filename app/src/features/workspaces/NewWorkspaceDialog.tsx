import * as React from 'react'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { AlertCircle, X } from 'lucide-react'
import { useAdminOrganizations, useCreateWorkspace } from '@/shell/orgQueries'
import { persistLastWorkspace } from '@/shell/WorkspaceSwitcher'
import '@/styles/auth-theme.css'

/**
 * Add a workspace to an organisation you administer.
 *
 * An account holds many workspaces — different teams, offices or clients —
 * and until now there was no way to make the second one: create_workspace
 * existed from the first migration but nothing ever called it. This is the
 * only entry point, gated on being an org owner or admin, which is also what
 * the RPC enforces.
 *
 * Intentionally one field. The organisation is only offered when you
 * administer more than one, because a select with a single option is a
 * decision nobody has to make.
 */

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
}

const FIELD: React.CSSProperties = {
  width: '100%', height: 42, borderRadius: 9, border: '1px solid #DCD3C8',
  background: '#FFFFFF', color: '#171310', fontFamily: 'var(--font-ui)',
  fontSize: 14, padding: '0 11px',
}

export function NewWorkspaceDialog({ open, onOpenChange }: Props) {
  const orgs = useAdminOrganizations()
  const create = useCreateWorkspace()
  const navigate = useNavigate()

  const [name, setName] = React.useState('')
  const [orgId, setOrgId] = React.useState<string | null>(null)
  const [error, setError] = React.useState<string | null>(null)
  const nameRef = React.useRef<HTMLInputElement>(null)
  // Ref, not state: a double click fires twice before React re-renders.
  const inFlight = React.useRef(false)

  const options = orgs.data ?? []
  const effectiveOrg = orgId ?? options[0]?.id ?? null

  React.useEffect(() => {
    if (!open) {
      setName(''); setOrgId(null); setError(null)
      inFlight.current = false
      return
    }
    const t = window.setTimeout(() => nameRef.current?.focus(), 0)
    return () => window.clearTimeout(t)
  }, [open])

  React.useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !create.isPending) { e.preventDefault(); onOpenChange(false) }
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, create.isPending, onOpenChange])

  if (!open) return null

  const trimmed = name.trim()
  const busy = create.isPending

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (inFlight.current) return
    if (!trimmed) { setError('Give the workspace a name.'); nameRef.current?.focus(); return }
    if (!effectiveOrg) { setError('No organisation to create this in.'); return }

    inFlight.current = true
    setError(null)
    create.mutate(
      { name: trimmed, organizationId: effectiveOrg },
      {
        onSuccess: (workspaceId) => {
          persistLastWorkspace(workspaceId)
          onOpenChange(false)
          toast.success('Workspace created')
          navigate(`/workspace/${workspaceId}/projects`)
        },
        onError: (err) => {
          inFlight.current = false
          const code = (err as { code?: string } | null)?.code
          setError(
            code === '42501'
              ? "You don't have permission to add a workspace to this organisation."
              : "Couldn't create the workspace. Check your connection and try again.",
          )
        },
      },
    )
  }

  return (
    <div
      onMouseDown={(e) => { if (e.target === e.currentTarget && !busy) onOpenChange(false) }}
      style={{
        position: 'fixed', inset: 0, zIndex: 50, background: 'rgba(23,19,16,.42)',
        display: 'grid', placeItems: 'center', padding: 16,
      }}
    >
      <div
        className="lign-warm"
        role="dialog"
        aria-modal="true"
        aria-labelledby="nw-title"
        style={{
          background: '#FFFFFF', border: '1px solid #E5DDD3', borderRadius: 14,
          boxShadow: '0 18px 44px rgba(23,19,16,.18)', width: 460, maxWidth: '100%',
        }}
      >
        <div style={{ padding: '20px 22px 16px', borderBottom: '1px solid #EFE8DF', display: 'flex', gap: 12 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <h2 id="nw-title" className="auth-display" style={{ margin: 0, fontSize: 23, lineHeight: 1.2 }}>
              New workspace
            </h2>
            <p style={{ margin: '6px 0 0', fontSize: 13, color: '#6B625A', lineHeight: 1.5 }}>
              Teams, offices and clients usually get one each. Projects live inside it.
            </p>
          </div>
          <button
            type="button" onClick={() => onOpenChange(false)} aria-label="Close" disabled={busy}
            style={{ background: 'none', border: 'none', cursor: busy ? 'not-allowed' : 'pointer', color: '#6B625A', width: 32, height: 32, borderRadius: 7, display: 'grid', placeItems: 'center', flex: '0 0 32px' }}
          >
            <X size={17} />
          </button>
        </div>

        <form onSubmit={onSubmit}>
          <div style={{ padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 16 }}>
            {error && (
              <div role="alert" style={{ background: '#FCF1EC', border: '1px solid #E8C4B3', borderRadius: 9, padding: '10px 12px', fontSize: 13, color: '#963015', display: 'flex', gap: 8 }}>
                <AlertCircle size={15} aria-hidden="true" style={{ color: '#A8341A', flex: '0 0 15px', marginTop: 1 }} />
                <span>{error}</span>
              </div>
            )}

            <div>
              <label htmlFor="nw-name" style={{ display: 'block', fontSize: 13, fontWeight: 500, color: '#3A332D', marginBottom: 6 }}>
                Workspace name
              </label>
              <input
                ref={nameRef} id="nw-name" value={name} disabled={busy} maxLength={120}
                placeholder="e.g. Northgate Team"
                onChange={(e) => { setName(e.target.value); if (error) setError(null) }}
                aria-invalid={error ? 'true' : undefined}
                style={FIELD}
              />
            </div>

            {options.length > 1 && (
              <div>
                <label htmlFor="nw-org" style={{ display: 'block', fontSize: 13, fontWeight: 500, color: '#3A332D', marginBottom: 6 }}>
                  Organisation
                </label>
                <select
                  id="nw-org" value={effectiveOrg ?? ''} disabled={busy}
                  onChange={(e) => setOrgId(e.target.value)}
                  style={FIELD}
                >
                  {options.map((o) => (
                    <option key={o.id} value={o.id}>{o.name}</option>
                  ))}
                </select>
              </div>
            )}
          </div>

          <div style={{ padding: '14px 22px', background: '#FBF9F6', borderTop: '1px solid #EFE8DF', borderRadius: '0 0 13px 13px', display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
            <button
              type="button" onClick={() => onOpenChange(false)} disabled={busy}
              style={{ height: 38, padding: '0 14px', borderRadius: 9, border: '1px solid #DCD3C8', background: '#FFFFFF', color: '#3A332D', fontSize: 13.5, cursor: busy ? 'not-allowed' : 'pointer' }}
            >
              Cancel
            </button>
            <button
              type="submit" disabled={!trimmed || busy} aria-busy={busy || undefined}
              style={{ height: 38, padding: '0 16px', borderRadius: 9, border: 'none', background: trimmed && !busy ? '#D9622B' : '#E5B69C', color: '#FFFFFF', fontSize: 13.5, fontWeight: 500, cursor: trimmed && !busy ? 'pointer' : 'not-allowed' }}
            >
              {busy ? 'Creating…' : 'Create workspace'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
