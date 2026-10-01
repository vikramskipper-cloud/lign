import * as React from 'react'
import { Navigate, useParams } from 'react-router'
import { toast } from 'sonner'
import { AlertCircle, Building2, Copy, Mail, Plus, X } from 'lucide-react'
import { useSession } from '@/auth/SessionProvider'
import {
  OrgInviteConflict, orgInviteUrl, useAddOrgMember, useAddableProfiles,
  useChangeOrgMemberRole, useInviteOrgMember, useMyOrganizations, useOrgMembers,
  useOrgInvitations, useRemoveOrgMember, useRevokeOrgInvitation,
  type OrgMember, type OrgRole,
} from '@/shell/orgQueries'
import { FullPageLoader } from '@/ui/full-page-loader'
import '@/styles/auth-theme.css'

export const OrgPeopleHandle = { crumb: 'Organisation people' }

/**
 * Who is in the organisation, and what they can see because of it.
 *
 * This is the one screen where a role genuinely spans workspaces, so it says
 * so plainly rather than leaving someone to discover that making a person an
 * admin here just handed them every workspace the company owns.
 *
 * TWO WAYS IN, because they answer different questions. "Add" takes someone
 * who already has an account you can see. "Invite" takes an email for someone
 * who does not, and hands back a link — there is still no email
 * infrastructure, so the link is copied and sent by hand, exactly as APP 013
 * settled for workspaces. The UI says that outright rather than implying an
 * email went out.
 *
 * Every rule here is enforced in the RPC, not on this screen: only an owner
 * may grant or revoke owner, nobody may change their own role, and the last
 * owner cannot be demoted or removed. The UI hides what it can and reports
 * what the database says when it cannot.
 */

const C = {
  border: '#DCD3C8', divider: '#EFE8DF', panelBorder: '#E5DDD3',
  ink: '#171310', text: '#3A332D', helper: '#6B625A',
  error: '#963015', errorIcon: '#A8341A',
  accent: '#D9622B', accentDisabled: '#E5B69C',
}

const ROLE_BLURB: Record<OrgRole, string> = {
  owner: 'Sees and administers every workspace. Controls the owner role itself.',
  admin: 'Sees and administers every workspace in the organisation.',
  member: 'No access by itself — workspaces are granted individually.',
}

function RoleChip({ role }: { role: OrgRole }) {
  const tone = role === 'owner'
    ? { fg: '#8A3A13', bg: '#FAEDE5' }
    : role === 'admin'
      ? { fg: '#7A5A18', bg: '#F7EFDC' }
      : { fg: '#5E554D', bg: '#F1ECE5' }
  return (
    <span
      className="auth-mono"
      style={{
        fontSize: 10, letterSpacing: '0.08em', padding: '2px 6px', borderRadius: 4,
        color: tone.fg, background: tone.bg, whiteSpace: 'nowrap',
      }}
    >
      {role.toUpperCase()}
    </span>
  )
}

export function OrgPeopleScreen() {
  const { org_id } = useParams<{ org_id: string }>()
  const { user } = useSession()
  const orgs = useMyOrganizations()

  const org = orgs.data?.find((o) => o.id === org_id)
  const members = useOrgMembers(org_id)
  const addable = useAddableProfiles(org_id)
  const add = useAddOrgMember(org_id ?? '')
  const changeRole = useChangeOrgMemberRole(org_id ?? '')
  const remove = useRemoveOrgMember(org_id ?? '')

  const invitations = useOrgInvitations(org_id)
  const invite = useInviteOrgMember(org_id ?? '')
  const revoke = useRevokeOrgInvitation(org_id ?? '')

  const [addId, setAddId] = React.useState('')
  const [addRole, setAddRole] = React.useState<OrgRole>('member')
  const [inviteEmail, setInviteEmail] = React.useState('')
  const [inviteRole, setInviteRole] = React.useState<OrgRole>('member')
  const [error, setError] = React.useState<string | null>(null)
  const [confirmRemove, setConfirmRemove] = React.useState<OrgMember | null>(null)
  const [lastLink, setLastLink] = React.useState<{ email: string; url: string } | null>(null)

  if (orgs.isLoading) return <FullPageLoader />
  // Not an org you belong to, or not one you administer: RLS would return an
  // empty list anyway, so say so rather than render an empty table.
  if (!org) return <Navigate to="/dashboard" replace />

  const iAmOwner = org.role === 'owner'
  const canAdminister = org.role === 'owner' || org.role === 'admin'
  if (!canAdminister) return <Navigate to="/dashboard" replace />

  const rows = members.data ?? []
  const owners = rows.filter((m) => m.role === 'owner' && m.status === 'active').length

  const fail = (err: unknown) => {
    const e = err as { code?: string; message?: string } | null
    // The RPC messages are written for people; surface them rather than
    // inventing copy that might contradict the actual rule that fired.
    setError(
      e?.code === '42501' || e?.code === '23514'
        ? (e.message ?? 'That change is not allowed.').replace(/^[a-z_]+: /, '')
        : "Couldn't apply that change. Check your connection and try again.",
    )
  }

  const onAdd = (e: React.FormEvent) => {
    e.preventDefault()
    if (!addId) return
    setError(null)
    add.mutate({ userId: addId, role: addRole }, {
      onSuccess: () => { setAddId(''); setAddRole('member'); toast.success('Added to the organisation') },
      onError: fail,
    })
  }

  const onInvite = (e: React.FormEvent) => {
    e.preventDefault()
    const email = inviteEmail.trim().toLowerCase()
    if (!email) return
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      setError("That doesn't look like an email address.")
      return
    }
    setError(null)
    setLastLink(null)
    invite.mutate({ email, role: inviteRole }, {
      onSuccess: (res) => {
        setInviteEmail('')
        setInviteRole('member')
        // Shown once and only once — the server keeps only its hash.
        setLastLink({ email, url: orgInviteUrl(res.token) })
        toast.success('Invitation created — copy the link')
      },
      onError: (err) => {
        if (err instanceof OrgInviteConflict) {
          setError(
            err.kind === 'member'
              ? `${err.email ?? email} is already in this organisation.`
              : `${err.email ?? email} already has a pending invitation. Revoke it to send a new one.`,
          )
          return
        }
        fail(err)
      },
    })
  }

  const field: React.CSSProperties = {
    height: 40, borderRadius: 9, border: `1px solid ${C.border}`, background: '#fff',
    color: C.ink, fontFamily: 'var(--font-ui)', fontSize: 14, padding: '0 11px',
  }

  return (
    <div className="lign-warm" style={{ padding: '28px 32px 56px', maxWidth: 900, margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <span aria-hidden="true" style={{ display: 'grid', placeItems: 'center', width: 34, height: 34, borderRadius: 9, background: 'var(--panel)', border: `1px solid ${C.panelBorder}`, flex: '0 0 34px' }}>
          <Building2 size={17} style={{ color: C.helper }} />
        </span>
        <div style={{ minWidth: 0 }}>
          <h1 className="auth-display" style={{ margin: 0, fontSize: 'clamp(24px, 4vw, 30px)', lineHeight: 1.15 }}>
            {org.name}
          </h1>
          <p style={{ margin: '6px 0 0', fontSize: 13.5, color: C.helper, lineHeight: 1.55 }}>
            Organisation roles span every workspace here. An owner or admin sees all of them;
            a member sees only the workspaces they are added to individually.
          </p>
        </div>
      </div>

      {error && (
        <div role="alert" style={{ marginTop: 20, background: '#FCF1EC', border: '1px solid #E8C4B3', borderRadius: 9, padding: '11px 13px', fontSize: 13.5, color: C.error, display: 'flex', gap: 8 }}>
          <AlertCircle size={15} aria-hidden="true" style={{ color: C.errorIcon, flex: '0 0 15px', marginTop: 1 }} />
          <span>{error}</span>
        </div>
      )}

      <section style={{ marginTop: 26 }}>
        <h2 style={{ margin: '0 0 10px', fontSize: 13, fontWeight: 600, color: C.ink }}>
          People ({rows.length})
        </h2>
        <div className="home-card">
          {members.isLoading && (
            <div style={{ padding: 16, fontSize: 13.5, color: C.helper }}>Loading…</div>
          )}
          {rows.map((m) => {
            const isMe = m.userId === user?.id
            // Mirrors the RPC guards so the control is absent rather than
            // offered and then refused.
            const lastOwner = m.role === 'owner' && owners <= 1
            const canTouch = !isMe && !lastOwner && (iAmOwner || m.role !== 'owner')
            return (
              <div key={m.memberId} className="home-row" style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <span style={{ fontSize: 14, color: C.ink }}>{m.name}</span>
                    {isMe && <span style={{ fontSize: 12, color: C.helper }}>(you)</span>}
                    <RoleChip role={m.role} />
                    {m.status !== 'active' && (
                      <span style={{ fontSize: 12, color: '#8A6420' }}>{m.status}</span>
                    )}
                  </div>
                  <p style={{ margin: '3px 0 0', fontSize: 12.5, color: C.helper }}>
                    {m.email} · {ROLE_BLURB[m.role]}
                  </p>
                </div>

                {canTouch ? (
                  <>
                    <label className="sr-only" htmlFor={`role-${m.memberId}`} style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }}>
                      Role for {m.name}
                    </label>
                    <select
                      id={`role-${m.memberId}`}
                      value={m.role}
                      disabled={changeRole.isPending}
                      onChange={(e) => {
                        setError(null)
                        changeRole.mutate({ memberId: m.memberId, role: e.target.value as OrgRole }, {
                          onSuccess: () => toast.success('Role updated'),
                          onError: fail,
                        })
                      }}
                      style={{ ...field, height: 34, fontSize: 13, flex: '0 0 auto' }}
                    >
                      <option value="member">member</option>
                      <option value="admin">admin</option>
                      {iAmOwner && <option value="owner">owner</option>}
                    </select>
                    <button
                      type="button"
                      onClick={() => { setError(null); setConfirmRemove(m) }}
                      disabled={remove.isPending}
                      style={{ height: 34, padding: '0 12px', borderRadius: 8, border: `1px solid ${C.border}`, background: '#fff', color: C.text, fontSize: 13, cursor: 'pointer', flex: '0 0 auto' }}
                    >
                      Remove
                    </button>
                  </>
                ) : (
                  <span style={{ fontSize: 12, color: C.helper, flex: '0 0 auto' }}>
                    {isMe ? 'You can’t change your own role' : lastOwner ? 'Last owner' : 'Owner — needs an owner'}
                  </span>
                )}
              </div>
            )
          })}
          {!members.isLoading && rows.length === 0 && (
            <div style={{ padding: 16, fontSize: 13.5, color: C.helper }}>Nobody yet.</div>
          )}
        </div>
      </section>

      {/* pending invitations ------------------------------------------- */}
      {(invitations.data ?? []).length > 0 && (
        <section style={{ marginTop: 26 }}>
          <h2 style={{ margin: '0 0 10px', fontSize: 13, fontWeight: 600, color: C.ink }}>
            Pending invitations ({(invitations.data ?? []).length})
          </h2>
          <div className="home-card">
            {(invitations.data ?? []).map((inv) => (
              <div key={inv.id} className="home-row" style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <span style={{ fontSize: 14, color: C.ink }}>{inv.email}</span>
                    <RoleChip role={inv.role} />
                  </div>
                  <p style={{ margin: '3px 0 0', fontSize: 12.5, color: C.helper }}>
                    Invited · expires {new Date(inv.expiresAt).toLocaleDateString()} · the link
                    was shown once when it was created
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setError(null)
                    revoke.mutate(inv.id, {
                      onSuccess: () => toast.success('Invitation revoked'),
                      onError: fail,
                    })
                  }}
                  disabled={revoke.isPending}
                  aria-label={`Revoke invitation for ${inv.email}`}
                  style={{ height: 34, padding: '0 12px', borderRadius: 8, border: `1px solid ${C.border}`, background: '#fff', color: C.text, fontSize: 13, cursor: 'pointer', flex: '0 0 auto' }}
                >
                  Revoke
                </button>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* invite by email ------------------------------------------------- */}
      <section style={{ marginTop: 26 }}>
        <h2 style={{ margin: '0 0 10px', fontSize: 13, fontWeight: 600, color: C.ink }}>
          Invite by email
        </h2>
        <form onSubmit={onInvite} className="home-card" style={{ padding: 14 }}>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'flex-end' }}>
            <div style={{ flex: '1 1 260px', minWidth: 0 }}>
              <label htmlFor="org-invite" style={{ display: 'block', fontSize: 13, fontWeight: 500, color: C.text, marginBottom: 6 }}>
                Email
              </label>
              <input
                id="org-invite" type="email" value={inviteEmail}
                onChange={(e) => { setInviteEmail(e.target.value); if (error) setError(null) }}
                disabled={invite.isPending}
                placeholder="name@company.com"
                style={{ ...field, width: '100%' }}
              />
            </div>
            <div style={{ flex: '0 0 150px' }}>
              <label htmlFor="org-invite-role" style={{ display: 'block', fontSize: 13, fontWeight: 500, color: C.text, marginBottom: 6 }}>
                Role
              </label>
              <select
                id="org-invite-role" value={inviteRole}
                onChange={(e) => setInviteRole(e.target.value as OrgRole)}
                disabled={invite.isPending}
                style={{ ...field, width: '100%' }}
              >
                <option value="member">member</option>
                <option value="admin">admin</option>
                {iAmOwner && <option value="owner">owner</option>}
              </select>
            </div>
            <button
              type="submit" disabled={!inviteEmail.trim() || invite.isPending}
              style={{ height: 40, padding: '0 14px', borderRadius: 9, border: 'none', display: 'flex', alignItems: 'center', gap: 6, background: inviteEmail.trim() && !invite.isPending ? C.accent : C.accentDisabled, color: '#fff', fontSize: 13.5, fontWeight: 500, cursor: inviteEmail.trim() && !invite.isPending ? 'pointer' : 'not-allowed' }}
            >
              <Mail size={14} aria-hidden="true" />
              {invite.isPending ? 'Creating…' : 'Create invite'}
            </button>
          </div>
          <p style={{ margin: '10px 0 0', fontSize: 12, color: C.helper, lineHeight: 1.5 }}>
            No email is sent — LIGN has no mail infrastructure yet. You get a link to pass on,
            shown once. Making someone an <strong>admin</strong> gives them every workspace in
            this organisation the moment they accept.
          </p>

          {lastLink && (
            <div style={{ marginTop: 12, background: '#FDFAF5', border: '1px solid #EBDCBB', borderRadius: 9, padding: '11px 12px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'space-between' }}>
                <p style={{ margin: 0, fontSize: 12.5, color: C.text }}>
                  Link for <strong>{lastLink.email}</strong> — copy it now, it is not shown again.
                </p>
                <button
                  type="button"
                  onClick={() => { void navigator.clipboard?.writeText(lastLink.url); toast.success('Copied') }}
                  style={{ height: 30, padding: '0 10px', borderRadius: 7, border: `1px solid ${C.border}`, background: '#fff', color: C.text, fontSize: 12.5, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 5, flex: '0 0 auto' }}
                >
                  <Copy size={13} aria-hidden="true" />
                  Copy
                </button>
              </div>
              <code className="auth-mono" style={{ display: 'block', marginTop: 7, fontSize: 11.5, color: C.helper, wordBreak: 'break-all' }}>
                {lastLink.url}
              </code>
              <button
                type="button" onClick={() => setLastLink(null)} aria-label="Dismiss link"
                style={{ marginTop: 6, background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: C.helper, fontSize: 12, display: 'flex', alignItems: 'center', gap: 4 }}
              >
                <X size={11} aria-hidden="true" /> Dismiss
              </button>
            </div>
          )}
        </form>
      </section>

      <section style={{ marginTop: 26 }}>
        <h2 style={{ margin: '0 0 10px', fontSize: 13, fontWeight: 600, color: C.ink }}>
          Add an existing account
        </h2>
        <form onSubmit={onAdd} className="home-card" style={{ padding: 14 }}>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'flex-end' }}>
            <div style={{ flex: '1 1 260px', minWidth: 0 }}>
              <label htmlFor="org-add" style={{ display: 'block', fontSize: 13, fontWeight: 500, color: C.text, marginBottom: 6 }}>
                Account
              </label>
              <select
                id="org-add" value={addId} onChange={(e) => setAddId(e.target.value)}
                disabled={add.isPending || addable.isLoading}
                style={{ ...field, width: '100%' }}
              >
                <option value="">Choose a person…</option>
                {(addable.data ?? []).map((p) => (
                  <option key={p.id} value={p.id}>{p.name} — {p.email}</option>
                ))}
              </select>
            </div>
            <div style={{ flex: '0 0 150px' }}>
              <label htmlFor="org-add-role" style={{ display: 'block', fontSize: 13, fontWeight: 500, color: C.text, marginBottom: 6 }}>
                Role
              </label>
              <select
                id="org-add-role" value={addRole} onChange={(e) => setAddRole(e.target.value as OrgRole)}
                disabled={add.isPending}
                style={{ ...field, width: '100%' }}
              >
                <option value="member">member</option>
                <option value="admin">admin</option>
                {iAmOwner && <option value="owner">owner</option>}
              </select>
            </div>
            <button
              type="submit" disabled={!addId || add.isPending}
              style={{ height: 40, padding: '0 14px', borderRadius: 9, border: 'none', display: 'flex', alignItems: 'center', gap: 6, background: addId && !add.isPending ? C.accent : C.accentDisabled, color: '#fff', fontSize: 13.5, fontWeight: 500, cursor: addId && !add.isPending ? 'pointer' : 'not-allowed' }}
            >
              <Plus size={14} aria-hidden="true" />
              {add.isPending ? 'Adding…' : 'Add'}
            </button>
          </div>
          <p style={{ margin: '10px 0 0', fontSize: 12, color: C.helper, lineHeight: 1.5 }}>
            For people who already have an account. Someone new goes through
            <strong> Invite by email</strong> above. Making someone an <strong>admin</strong>
            gives them every workspace in this organisation immediately.
          </p>
        </form>
      </section>

      {confirmRemove && (
        <div
          role="dialog" aria-modal="true" aria-labelledby="rm-title"
          style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(23,19,16,.42)', display: 'grid', placeItems: 'center', padding: 16 }}
        >
          <div className="lign-warm" style={{ background: '#fff', border: `1px solid ${C.panelBorder}`, borderRadius: 14, boxShadow: '0 18px 44px rgba(23,19,16,.18)', width: 400, maxWidth: '100%', padding: 20 }}>
            <h3 id="rm-title" className="auth-display" style={{ margin: 0, fontSize: 20 }}>
              Remove {confirmRemove.name}?
            </h3>
            <p style={{ margin: '8px 0 0', fontSize: 13.5, color: C.helper, lineHeight: 1.55 }}>
              They lose organisation-wide access. Workspaces they were added to individually
              are <strong>not</strong> touched — remove those separately if you mean to.
            </p>
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10, marginTop: 18 }}>
              <button
                type="button" autoFocus onClick={() => setConfirmRemove(null)}
                style={{ height: 38, padding: '0 14px', borderRadius: 9, border: `1px solid ${C.border}`, background: '#fff', color: C.text, fontSize: 13.5, cursor: 'pointer' }}
              >
                Keep
              </button>
              <button
                type="button"
                onClick={() => {
                  const m = confirmRemove
                  setConfirmRemove(null)
                  remove.mutate(m.memberId, {
                    onSuccess: () => toast.success('Removed from the organisation'),
                    onError: fail,
                  })
                }}
                style={{ height: 38, padding: '0 14px', borderRadius: 9, border: 'none', background: C.accent, color: '#fff', fontSize: 13.5, fontWeight: 500, cursor: 'pointer' }}
              >
                Remove
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
