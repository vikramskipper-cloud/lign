import * as React from 'react'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { AlertCircle, ChevronDown, X } from 'lucide-react'
import { useSession } from '@/auth/SessionProvider'
import { useWorkspace } from '@/shell/queries'
import {
  CODE_RE, CodeTakenError, EMAIL_RE, PermissionError, deriveCode, suggestCode,
  useCodeAvailability, useCreateProject, useWorkspaceMemberOptions,
  type CreatedInvite,
} from './newProject'
import '@/styles/auth-theme.css'

/**
 * New project — one required field, everything else optional.
 *
 * The whole creation is one RPC (create_project_full). Nothing here writes a
 * row directly, and nothing here decides permissions: the button is hidden
 * without workspace.manage, but the RPC is what says no.
 *
 * NOT built on ui/dialog.tsx. That is the zinc-themed Radix dialog the rest of
 * the app uses; this follows the warm spec, needs a fixed header and footer
 * with an independently scrolling body, and turns into a full-screen sheet
 * under 640px. Focus trap, Esc and scrim are implemented here rather than
 * inherited — see the trap below.
 */

const C = {
  border: '#DCD3C8', divider: '#EFE8DF', panelBorder: '#E5DDD3',
  ink: '#171310', text: '#3A332D', helper: '#6B625A',
  error: '#963015', errorIcon: '#A8341A', errorBorder: '#C97C5E',
  accent: '#D9622B', accentDisabled: '#E5B69C',
  clientBg: '#FDFAF5', clientBorder: '#EBDCBB',
  chipFg: '#7A5A18', chipBg: '#F7EFDC',
  footerBg: '#FBF9F6',
}

interface ClientRow {
  email: string
  /** Set when the address turns out to belong to an existing member. */
  memberName: string | null
}

interface Props {
  workspaceId: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

function Label({
  htmlFor, children, optional,
}: { htmlFor: string; children: React.ReactNode; optional?: boolean }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 6 }}>
      <label htmlFor={htmlFor} style={{ fontSize: 13, fontWeight: 500, color: C.text }}>
        {children}
      </label>
      {optional && <span style={{ fontSize: 12, color: C.helper }}>Optional</span>}
    </div>
  )
}

function Helper({ id, children }: { id?: string; children: React.ReactNode }) {
  return <p id={id} style={{ margin: '6px 0 0', fontSize: 12, color: C.helper, lineHeight: 1.45 }}>{children}</p>
}

function FieldError({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <p id={id} style={{ margin: '6px 0 0', fontSize: 12, color: C.error, display: 'flex', alignItems: 'flex-start', gap: 5, lineHeight: 1.45 }}>
      <AlertCircle size={13} aria-hidden="true" style={{ color: C.errorIcon, flex: '0 0 13px', marginTop: 1 }} />
      <span>{children}</span>
    </p>
  )
}

const field = (invalid: boolean): React.CSSProperties => ({
  width: '100%',
  height: 42,
  borderRadius: 9,
  border: `1px solid ${invalid ? C.errorBorder : C.border}`,
  background: '#FFFFFF',
  color: C.ink,
  fontFamily: 'var(--font-ui)',
  fontSize: 14,
  padding: '0 11px',
})

export function NewProjectDialog({ workspaceId, open, onOpenChange }: Props) {
  const { user } = useSession()
  const navigate = useNavigate()
  const workspace = useWorkspace(workspaceId)
  const members = useWorkspaceMemberOptions(workspaceId)
  const create = useCreateProject(workspaceId)

  const [name, setName] = React.useState('')
  const [code, setCode] = React.useState('')
  const [codeTouched, setCodeTouched] = React.useState(false)
  const [leadMemberId, setLeadMemberId] = React.useState<string | null>(null)
  const [clients, setClients] = React.useState<ClientRow[]>([])
  const [clientDraft, setClientDraft] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [more, setMore] = React.useState(false)

  const [errors, setErrors] = React.useState<{ name?: string; code?: string; client?: string }>({})
  const [banner, setBanner] = React.useState<string | null>(null)
  const [confirmDiscard, setConfirmDiscard] = React.useState(false)
  const [announce, setAnnounce] = React.useState('')

  const dialogRef = React.useRef<HTMLDivElement>(null)
  const nameRef = React.useRef<HTMLInputElement>(null)
  const codeRef = React.useRef<HTMLInputElement>(null)
  const clientRef = React.useRef<HTMLInputElement>(null)
  // Ref, not state: a double click fires twice before React re-renders, and
  // creating two projects from one intent is the failure that matters here.
  const inFlight = React.useRef(false)

  const myMemberId = members.data?.find((m) => m.userId === user?.id)?.memberId ?? null
  const effectiveLead = leadMemberId ?? myMemberId
  const leadIsSomeoneElse = Boolean(effectiveLead && myMemberId && effectiveLead !== myMemberId)

  const trimmedName = name.trim()
  const canSubmit = trimmedName.length > 0 && !create.isPending

  // Debounced rather than per-keystroke: the probe is a round trip, and
  // "NGF" typed a character at a time would fire three of them. Blur commits
  // the current value immediately so leaving the field always checks.
  const [probe, setProbe] = React.useState('')
  React.useEffect(() => {
    const id = window.setTimeout(() => setProbe(code.trim().toUpperCase()), 400)
    return () => window.clearTimeout(id)
  }, [code])
  const availability = useCodeAvailability(workspaceId, errors.code ? '' : probe)

  const reset = React.useCallback(() => {
    setName(''); setCode(''); setCodeTouched(false); setLeadMemberId(null)
    setClients([]); setClientDraft(''); setDescription(''); setMore(false)
    setErrors({}); setBanner(null); setConfirmDiscard(false); setAnnounce('')
    inFlight.current = false
  }, [])

  React.useEffect(() => { if (!open) reset() }, [open, reset])

  React.useEffect(() => {
    if (open) {
      const t = window.setTimeout(() => nameRef.current?.focus(), 0)
      return () => window.clearTimeout(t)
    }
  }, [open])

  // Auto-derive the code until the user takes it over. Once they have typed in
  // the field it is theirs, and later edits to the name must not overwrite it.
  React.useEffect(() => {
    if (!codeTouched) setCode(deriveCode(name))
  }, [name, codeTouched])

  const dirty =
    trimmedName.length > 0 || clients.length > 0 || clientDraft.trim().length > 0 ||
    description.trim().length > 0 || (codeTouched && code.trim().length > 0) ||
    Boolean(leadMemberId && leadMemberId !== myMemberId)

  const requestClose = React.useCallback(() => {
    if (create.isPending) return
    if (dirty) { setConfirmDiscard(true); return }
    onOpenChange(false)
  }, [dirty, create.isPending, onOpenChange])

  // Focus trap + Esc. Implemented here because this dialog is not the Radix
  // one; both behaviours are required by the spec and neither comes for free.
  React.useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        if (confirmDiscard) { setConfirmDiscard(false); return }
        requestClose()
        return
      }
      if (e.key !== 'Tab') return
      const root = dialogRef.current
      if (!root) return
      const focusable = root.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      )
      if (focusable.length === 0) return
      const first = focusable[0]!
      const last = focusable[focusable.length - 1]!
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus() }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKey)
    const prevOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = prevOverflow
    }
  }, [open, confirmDiscard, requestClose])

  if (!open) return null

  const addClient = () => {
    const raw = clientDraft.trim().toLowerCase()
    if (!raw) return
    if (!EMAIL_RE.test(raw)) {
      setErrors((p) => ({ ...p, client: "That doesn't look like an email address." }))
      clientRef.current?.focus()
      return
    }
    if (clients.some((c) => c.email === raw)) {
      setErrors((p) => ({ ...p, client: 'Already added.' }))
      clientRef.current?.focus()
      return
    }
    // One human must never end up with two identities in a workspace, so an
    // address that already belongs to a member is flagged here and resolved to
    // that member by the RPC.
    const member = members.data?.find((m) => m.email === raw)
    setClients((p) => [...p, { email: raw, memberName: member?.name ?? null }])
    setClientDraft('')
    setErrors((p) => ({ ...p, client: undefined }))
    setAnnounce(
      member
        ? `${raw} added. ${member.name} is already in this workspace and will be added as an internal approver.`
        : `${raw} added as an external approver. Invite sends on create.`,
    )
  }

  const removeClient = (email: string) => {
    setClients((p) => p.filter((c) => c.email !== email))
    setAnnounce(`${email} removed.`)
  }

  const externalCount = clients.filter((c) => !c.memberName).length

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (inFlight.current) return

    const next: typeof errors = {}
    if (!trimmedName) next.name = 'Give the project a name.'
    else if (trimmedName.length > 120) next.name = 'Max 120 characters.'
    const codeValue = code.trim().toUpperCase()
    if (codeValue && !CODE_RE.test(codeValue)) {
      next.code = 'Letters, digits and dashes only (max 16), starting with a letter or digit.'
    } else if (codeValue && availability.data && !availability.data.available) {
      next.code = `${codeValue} is already used by ${availability.data.conflictName}. Try ${suggestCode(codeValue)}.`
    }
    setErrors(next)
    if (next.name) { nameRef.current?.focus(); return }
    if (next.code) { codeRef.current?.focus(); return }

    inFlight.current = true
    setBanner(null)
    create.mutate(
      {
        name: trimmedName,
        code: codeValue || null,
        description: description.trim() || null,
        leadMemberId: leadIsSomeoneElse ? effectiveLead : null,
        clientEmails: clients.map((c) => c.email),
      },
      {
        onSuccess: (result) => {
          onOpenChange(false)
          toast.success('Project created')
          surfaceInvites(result.invites)
          navigate(`/workspace/${workspaceId}/project/${result.projectId}/overview`)
        },
        onError: (err) => {
          inFlight.current = false
          if (err instanceof CodeTakenError) {
            const taken = codeValue
            setErrors({
              code: `${taken} is already used by ${err.conflictName ?? 'another project'}. Try ${suggestCode(taken)}.`,
            })
            codeRef.current?.focus()
            return
          }
          if (err instanceof PermissionError) {
            onOpenChange(false)
            toast.error("You don't have permission to create projects in this workspace.")
            return
          }
          setBanner("Couldn't create the project. Check your connection and try again.")
        },
      },
    )
  }

  const busy = create.isPending

  return (
    <>
      <div
        onMouseDown={(e) => { if (e.target === e.currentTarget) requestClose() }}
        style={{
          position: 'fixed', inset: 0, zIndex: 50, background: 'rgba(23,19,16,.42)',
          display: 'grid', placeItems: 'center', padding: 16,
        }}
      >
        <div
          ref={dialogRef}
          className="lign-warm np-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="np-title"
          style={{
            background: '#FFFFFF', border: `1px solid ${C.panelBorder}`, borderRadius: 14,
            boxShadow: '0 18px 44px rgba(23,19,16,.18)', width: 520, maxWidth: '100%',
            maxHeight: '100%', display: 'flex', flexDirection: 'column', minHeight: 0,
          }}
        >
          {/* header ------------------------------------------------------ */}
          <div style={{ padding: '20px 22px 16px', borderBottom: `1px solid ${C.divider}`, display: 'flex', gap: 12, flex: '0 0 auto' }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <h2 id="np-title" className="auth-display" style={{ margin: 0, fontSize: 25, lineHeight: 1.2 }}>
                New project
              </h2>
              <p style={{ margin: '6px 0 0', fontSize: 13, color: C.helper, lineHeight: 1.5 }}>
                In {workspace.data?.name ?? 'this workspace'}. You can add people and requirements once it exists.
              </p>
            </div>
            <button
              type="button" onClick={requestClose} aria-label="Close" disabled={busy}
              style={{ background: 'none', border: 'none', cursor: busy ? 'not-allowed' : 'pointer', color: C.helper, width: 32, height: 32, borderRadius: 7, display: 'grid', placeItems: 'center', flex: '0 0 32px' }}
            >
              <X size={17} />
            </button>
          </div>

          <form onSubmit={onSubmit} style={{ display: 'contents' }}>
            {/* body ------------------------------------------------------ */}
            <div style={{ padding: '20px 22px', overflowY: 'auto', flex: '1 1 auto', minHeight: 0, display: 'flex', flexDirection: 'column', gap: 18 }}>
              {banner && (
                <div role="alert" style={{ background: '#FCF1EC', border: '1px solid #E8C4B3', borderRadius: 9, padding: '10px 12px', fontSize: 13, color: C.error, display: 'flex', gap: 8 }}>
                  <AlertCircle size={15} aria-hidden="true" style={{ color: C.errorIcon, flex: '0 0 15px', marginTop: 1 }} />
                  <span>{banner}</span>
                </div>
              )}

              {/* name */}
              <div>
                <Label htmlFor="np-name">Project name</Label>
                <input
                  ref={nameRef} id="np-name" value={name} disabled={busy} maxLength={120}
                  onChange={(e) => { setName(e.target.value); if (errors.name) setErrors((p) => ({ ...p, name: undefined })) }}
                  placeholder="e.g. Northgate Flagship"
                  aria-invalid={errors.name ? 'true' : undefined}
                  aria-describedby={errors.name ? 'np-name-err' : undefined}
                  style={field(Boolean(errors.name))}
                />
                {errors.name && <FieldError id="np-name-err">{errors.name}</FieldError>}
              </div>

              {/* code */}
              <div>
                <Label htmlFor="np-code" optional>Project code</Label>
                <input
                  ref={codeRef} id="np-code" value={code} disabled={busy} maxLength={16}
                  onChange={(e) => {
                    setCodeTouched(true)
                    setCode(e.target.value.toUpperCase())
                    if (errors.code) setErrors((p) => ({ ...p, code: undefined }))
                  }}
                  onBlur={() => setProbe(code.trim().toUpperCase())}
                  aria-invalid={errors.code ? 'true' : undefined}
                  aria-describedby={errors.code ? 'np-code-err' : 'np-code-help'}
                  className="auth-mono"
                  style={{ ...field(Boolean(errors.code)), letterSpacing: '0.06em' }}
                />
                {errors.code ? (
                  <FieldError id="np-code-err">{errors.code}</FieldError>
                ) : availability.data && !availability.data.available && probe === code.trim().toUpperCase() ? (
                  <FieldError id="np-code-err">
                    {probe} is already used by {availability.data.conflictName}. Try {suggestCode(probe)}.
                  </FieldError>
                ) : (
                  <Helper id="np-code-help">
                    Prefixes IDs across the project — {code || 'NGF'}-RLS-07. Unique within this workspace.
                  </Helper>
                )}
              </div>

              {/* lead */}
              <div>
                <Label htmlFor="np-lead">Project lead</Label>
                <div style={{ position: 'relative' }}>
                  <select
                    id="np-lead" disabled={busy || members.isLoading}
                    value={effectiveLead ?? ''}
                    onChange={(e) => setLeadMemberId(e.target.value || null)}
                    style={{ ...field(false), appearance: 'none', paddingRight: 34 }}
                  >
                    {(members.data ?? []).map((m) => (
                      <option key={m.memberId} value={m.memberId}>
                        {m.memberId === myMemberId ? `${m.name} (you)` : m.name}
                      </option>
                    ))}
                  </select>
                  <ChevronDown size={15} aria-hidden="true" style={{ position: 'absolute', right: 11, top: '50%', transform: 'translateY(-50%)', color: C.helper, pointerEvents: 'none' }} />
                </div>
                <Helper>
                  The lead can upload versions, create releases and manage access. Hand it to someone else
                  now, or later in People.
                </Helper>
                {leadIsSomeoneElse && (
                  <Helper>You&apos;ll be added as a contributor so you keep access after handing over.</Helper>
                )}
              </div>

              <hr style={{ border: 0, borderTop: `1px solid ${C.divider}`, margin: 0 }} />

              {/* clients */}
              <div>
                <Label htmlFor="np-client" optional>Client approver</Label>
                <div style={{ display: 'flex', gap: 8 }}>
                  <input
                    ref={clientRef} id="np-client" type="email" value={clientDraft} disabled={busy}
                    onChange={(e) => { setClientDraft(e.target.value); if (errors.client) setErrors((p) => ({ ...p, client: undefined })) }}
                    onKeyDown={(e) => {
                      // Enter adds the address here instead of submitting the
                      // form — submitting mid-entry would silently drop it.
                      if (e.key === 'Enter') { e.preventDefault(); addClient() }
                    }}
                    placeholder="name@client.com"
                    aria-invalid={errors.client ? 'true' : undefined}
                    aria-describedby={errors.client ? 'np-client-err' : 'np-client-help'}
                    style={{ ...field(Boolean(errors.client)), flex: 1 }}
                  />
                  <button
                    type="button" onClick={addClient} disabled={busy || !clientDraft.trim()}
                    style={{ height: 42, padding: '0 14px', borderRadius: 9, border: `1px solid ${C.border}`, background: '#FFFFFF', color: C.text, fontSize: 13.5, cursor: clientDraft.trim() ? 'pointer' : 'not-allowed', flex: '0 0 auto' }}
                  >
                    Add
                  </button>
                </div>
                {errors.client ? (
                  <FieldError id="np-client-err">{errors.client}</FieldError>
                ) : (
                  <Helper id="np-client-help">
                    They&apos;ll be added as an external approver and emailed an invite on create. No Lign
                    account needed to respond.
                  </Helper>
                )}

                <div aria-live="polite" style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }}>
                  {announce}
                </div>

                {clients.length > 0 && (
                  <ul style={{ listStyle: 'none', margin: '10px 0 0', padding: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
                    {clients.map((c) => (
                      <li
                        key={c.email}
                        style={{ background: C.clientBg, border: `1px solid ${C.clientBorder}`, borderRadius: 9, padding: '9px 10px', display: 'flex', alignItems: 'center', gap: 9 }}
                      >
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 7, flexWrap: 'wrap' }}>
                            <span style={{ fontSize: 13.5, color: C.ink, overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.email}</span>
                            {!c.memberName && (
                              <span className="auth-mono" style={{ fontSize: 10, letterSpacing: '0.08em', padding: '2px 6px', borderRadius: 4, color: C.chipFg, background: C.chipBg }}>
                                EXTERNAL
                              </span>
                            )}
                          </div>
                          <p style={{ margin: '3px 0 0', fontSize: 12, color: C.helper }}>
                            {c.memberName
                              ? `${c.memberName} is already in this workspace. They'll be added as an internal approver instead.`
                              : 'Approver · invite sends on create'}
                          </p>
                        </div>
                        <button
                          type="button" onClick={() => removeClient(c.email)} disabled={busy}
                          aria-label={`Remove ${c.email}`}
                          style={{ background: 'none', border: 'none', cursor: 'pointer', color: C.helper, width: 28, height: 28, borderRadius: 6, display: 'grid', placeItems: 'center', flex: '0 0 28px' }}
                        >
                          <X size={14} />
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              <hr style={{ border: 0, borderTop: `1px solid ${C.divider}`, margin: 0 }} />

              {/* more options */}
              <div>
                <button
                  type="button" onClick={() => setMore((v) => !v)} aria-expanded={more}
                  aria-controls="np-more"
                  style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: C.text, fontSize: 13, fontWeight: 500, display: 'flex', alignItems: 'center', gap: 5, minHeight: 28 }}
                >
                  <ChevronDown size={14} aria-hidden="true" style={{ transform: more ? 'rotate(0deg)' : 'rotate(-90deg)', transition: 'transform 120ms ease' }} />
                  More options
                </button>
                {more && (
                  <div id="np-more" style={{ marginTop: 12 }}>
                    <Label htmlFor="np-desc" optional>Description</Label>
                    <input
                      id="np-desc" value={description} disabled={busy} maxLength={280}
                      onChange={(e) => setDescription(e.target.value)}
                      placeholder="One line on what this project covers"
                      style={field(false)}
                    />
                    <Helper>
                      Discipline and target completion aren&apos;t stored yet — see the APP 014 report.
                      Adding them here would discard what you typed.
                    </Helper>
                  </div>
                )}
              </div>
            </div>

            {/* footer ---------------------------------------------------- */}
            <div
              className="np-footer"
              style={{ padding: '14px 22px', background: C.footerBg, borderTop: `1px solid ${C.divider}`, borderRadius: '0 0 13px 13px', display: 'flex', alignItems: 'center', gap: 12, flex: '0 0 auto' }}
            >
              <p style={{ margin: 0, flex: 1, fontSize: 12.5, color: C.helper }}>
                {externalCount > 0
                  ? `${externalCount} invite ${externalCount === 1 ? 'email' : 'emails'} will be sent when you create.`
                  : ''}
              </p>
              <button
                type="button" onClick={requestClose} disabled={busy}
                style={{ height: 38, padding: '0 14px', borderRadius: 9, border: `1px solid ${C.border}`, background: '#FFFFFF', color: C.text, fontSize: 13.5, cursor: busy ? 'not-allowed' : 'pointer' }}
              >
                Cancel
              </button>
              <button
                type="submit" disabled={!canSubmit} aria-busy={busy || undefined}
                style={{ height: 38, padding: '0 16px', borderRadius: 9, border: 'none', background: canSubmit ? C.accent : C.accentDisabled, color: '#FFFFFF', fontSize: 13.5, fontWeight: 500, cursor: canSubmit ? 'pointer' : 'not-allowed' }}
              >
                {busy ? 'Creating…' : 'Create project'}
              </button>
            </div>
          </form>
        </div>
      </div>

      {confirmDiscard && (
        <div
          role="dialog" aria-modal="true" aria-labelledby="np-discard-title"
          style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(23,19,16,.42)', display: 'grid', placeItems: 'center', padding: 16 }}
        >
          <div className="lign-warm" style={{ background: '#FFFFFF', border: `1px solid ${C.panelBorder}`, borderRadius: 14, boxShadow: '0 18px 44px rgba(23,19,16,.18)', width: 380, maxWidth: '100%', padding: 20 }}>
            <h3 id="np-discard-title" className="auth-display" style={{ margin: 0, fontSize: 20 }}>Discard this project?</h3>
            <p style={{ margin: '8px 0 0', fontSize: 13.5, color: C.helper, lineHeight: 1.5 }}>
              What you&apos;ve typed will be lost. Nothing has been created yet.
            </p>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 18 }}>
              <button
                type="button" autoFocus onClick={() => setConfirmDiscard(false)}
                style={{ height: 38, padding: '0 14px', borderRadius: 9, border: `1px solid ${C.border}`, background: '#FFFFFF', color: C.text, fontSize: 13.5, cursor: 'pointer' }}
              >
                Keep editing
              </button>
              <button
                type="button" onClick={() => { setConfirmDiscard(false); onOpenChange(false) }}
                style={{ height: 38, padding: '0 14px', borderRadius: 9, border: 'none', background: C.accent, color: '#FFFFFF', fontSize: 13.5, fontWeight: 500, cursor: 'pointer' }}
              >
                Discard
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

/**
 * There is no email infrastructure — APP 013 settled on copy-link delivery and
 * nothing has changed. The invite rows and their one-time tokens are created
 * inside the transaction; "sending" is the lead passing on a link. Rather than
 * claim an email went out, the links are handed over immediately.
 */
function surfaceInvites(invites: CreatedInvite[]) {
  const external = invites.filter((i) => i.kind === 'stakeholder' && i.token)
  if (external.length === 0) return
  toast.info(
    `${external.length} invite ${external.length === 1 ? 'link' : 'links'} ready — no email was sent`,
    {
      duration: 30_000,
      description: external.map((i) => i.email).join(', '),
      action: {
        label: external.length === 1 ? 'Copy link' : 'Copy links',
        onClick: () => {
          const text = external
            .map((i) => `${i.email}: ${window.location.origin}/invite/${i.token}`)
            .join('\n')
          void navigator.clipboard?.writeText(text)
          toast.success('Copied')
        },
      },
    },
  )
}
