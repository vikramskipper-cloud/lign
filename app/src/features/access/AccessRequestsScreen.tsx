import * as React from 'react'
import { Navigate } from 'react-router'
import { toast } from 'sonner'
import { Mail, Phone, Users, Clock } from 'lucide-react'
import {
  useAccessRequests,
  useDecideAccessRequest,
  useEmailOutbox,
  useIsPlatformAdmin,
  type AccessRequest,
  type AccessRequestStatus,
} from '@/features/access/accessRequests'
import { FullPageLoader } from '@/ui/full-page-loader'

/**
 * APP 020 — triage for the public request-access form. Re-gated by APP 021.
 *
 * LIGN PLATFORM ADMINS ONLY — not organisation admins. An applicant is a
 * stranger who belongs to no organisation; deciding whether they may use LIGN
 * is the vendor's call, and their name, work email and phone number are not a
 * customer's to read. APP 020 had this wrong and gated on org role.
 *
 * The gate is re-checked here as well as in the database because RLS returns
 * an EMPTY LIST to anyone else rather than an error — so "no rows" cannot be
 * read as "nothing pending", and a screen that inferred it would report an
 * empty queue to someone who simply could not see it.
 *
 * Approving records the decision and queues the outcome email. It deliberately
 * does NOT issue an invitation: whether someone joins an organisation or a
 * single project as an external client is a separate, explicit choice. Approval
 * here means "yes, let them in" — it is not itself the letting in.
 */

export const AccessRequestsHandle = { crumb: 'Access requests' }

const TABS: { key: AccessRequestStatus | 'all'; label: string }[] = [
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Declined' },
  { key: 'all', label: 'All' },
]

const TEAM_SIZE_LABEL: Record<string, string> = {
  '1': 'Just them',
  '2-5': '2–5 people',
  '6-20': '6–20 people',
  '21-50': '21–50 people',
  '51-200': '51–200 people',
  '200+': '200+ people',
}

function when(iso: string): string {
  const then = new Date(iso).getTime()
  const mins = Math.round((Date.now() - then) / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.round(hours / 24)
  if (days < 30) return `${days}d ago`
  return new Date(iso).toLocaleDateString()
}

const CARD: React.CSSProperties = {
  background: 'var(--surface)',
  border: '1px solid var(--panel-border)',
  borderRadius: 10,
  padding: '16px 18px',
}

const META: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 6,
  fontSize: 13,
  color: 'var(--muted)',
  minWidth: 0,
}

function RequestCard({ request }: { request: AccessRequest }) {
  const decide = useDecideAccessRequest()
  const [note, setNote] = React.useState('')
  const [showNote, setShowNote] = React.useState(false)
  // Ref, not state: two clicks before a re-render would fire two decisions,
  // and the second gets a 23514 the user never asked to see.
  const inFlight = React.useRef(false)

  const act = (approve: boolean) => {
    if (inFlight.current) return
    inFlight.current = true
    decide.mutate(
      { id: request.id, approve, note },
      {
        onSuccess: () => {
          toast.success(
            approve
              ? `Approved — a confirmation email is queued for ${request.email}`
              : `Declined ${request.name}`,
          )
        },
        onError: (err) => {
          inFlight.current = false
          const code = (err as { code?: string } | null)?.code
          toast.error(
            code === '23514'
              ? 'Someone else has already decided this one.'
              : code === '42501'
                ? 'Only LIGN platform administrators can decide requests.'
                : "Couldn't record that. Try again.",
          )
        },
      },
    )
  }

  const busy = decide.isPending

  return (
    <div style={CARD}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
        <h2 style={{ margin: 0, fontSize: 15.5, fontWeight: 600, color: 'var(--ink)' }}>
          {request.name}
        </h2>
        <span style={{ fontSize: 13, color: 'var(--muted)' }}>{request.companyRole}</span>
        <span style={{ flex: 1 }} />
        <span style={{ ...META, gap: 5, flex: '0 0 auto' }}>
          <Clock size={12} aria-hidden="true" />
          {when(request.createdAt)}
        </span>
      </div>

      <div
        style={{
          display: 'flex',
          gap: 18,
          flexWrap: 'wrap',
          marginTop: 10,
          paddingTop: 10,
          borderTop: '1px solid var(--row-divider)',
        }}
      >
        <span style={META}>
          <Mail size={13} aria-hidden="true" />
          <a href={`mailto:${request.email}`} className="auth-link" style={{ fontSize: 13 }}>
            {request.email}
          </a>
        </span>
        {request.phone && (
          <span style={META}>
            <Phone size={13} aria-hidden="true" />
            {request.phone}
          </span>
        )}
        <span style={META}>
          <Users size={13} aria-hidden="true" />
          {TEAM_SIZE_LABEL[request.teamSize] ?? request.teamSize}
        </span>
      </div>

      {request.status === 'pending' ? (
        <>
          {showNote && (
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={busy}
              rows={2}
              placeholder="Internal note (optional) — kept on the record, not emailed"
              style={{
                width: '100%',
                marginTop: 12,
                padding: '9px 11px',
                background: 'var(--surface)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-field)',
                color: 'var(--ink)',
                fontFamily: 'var(--font-ui)',
                fontSize: 14,
                lineHeight: 1.45,
                resize: 'vertical',
              }}
            />
          )}
          <div style={{ display: 'flex', gap: 9, marginTop: 13, alignItems: 'center' }}>
            <button
              type="button"
              onClick={() => act(true)}
              disabled={busy}
              style={{
                height: 34,
                padding: '0 15px',
                background: 'var(--accent)',
                color: '#fff',
                border: 'none',
                borderRadius: 8,
                fontSize: 13.5,
                fontWeight: 500,
                cursor: busy ? 'not-allowed' : 'pointer',
                opacity: busy ? 0.6 : 1,
              }}
            >
              {busy ? 'Saving…' : 'Approve'}
            </button>
            <button
              type="button"
              onClick={() => act(false)}
              disabled={busy}
              style={{
                height: 34,
                padding: '0 15px',
                background: 'none',
                color: 'var(--text)',
                border: '1px solid var(--border)',
                borderRadius: 8,
                fontSize: 13.5,
                cursor: busy ? 'not-allowed' : 'pointer',
                opacity: busy ? 0.6 : 1,
              }}
            >
              Decline
            </button>
            {!showNote && (
              <button
                type="button"
                onClick={() => setShowNote(true)}
                disabled={busy}
                className="auth-link"
                style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', fontSize: 13 }}
              >
                Add a note
              </button>
            )}
          </div>
        </>
      ) : (
        <p style={{ margin: '12px 0 0', fontSize: 13, color: 'var(--muted)' }}>
          <strong
            style={{
              fontWeight: 500,
              color: request.status === 'approved' ? 'var(--status-approved-text)' : 'var(--muted)',
            }}
          >
            {request.status === 'approved' ? 'Approved' : 'Declined'}
          </strong>
          {request.decidedBy ? ` by ${request.decidedBy.name}` : ''}
          {request.decidedAt ? ` · ${when(request.decidedAt)}` : ''}
          {request.note ? ` · “${request.note}”` : ''}
        </p>
      )}
    </div>
  )
}

export function AccessRequestsScreen() {
  const isOperator = useIsPlatformAdmin()
  const [tab, setTab] = React.useState<AccessRequestStatus | 'all'>('pending')
  const requests = useAccessRequests(tab, isOperator.data === true)
  const outbox = useEmailOutbox('queued', isOperator.data === true)

  if (isOperator.isLoading) return <FullPageLoader label="Loading" />
  // Not a platform operator: RLS would hand back an empty list, which would
  // read as "nothing pending". Leave rather than show a false empty queue.
  if (isOperator.data !== true) return <Navigate to="/dashboard" replace />

  const rows = requests.data ?? []
  const queued = outbox.data?.length ?? 0

  return (
    <div className="lign-warm" style={{ maxWidth: 820, margin: '0 auto', padding: '28px 24px 48px' }}>
      <h1 className="auth-display" style={{ fontSize: 28, lineHeight: 1.15, margin: 0 }}>
        Access requests
      </h1>
      <p style={{ margin: '8px 0 0', fontSize: 14.5, lineHeight: 1.6, color: 'var(--muted)' }}>
        People asking to use LIGN. Approving records the decision and queues them an email — it does
        not grant access on its own. Admit them by adding them to an organisation, or have a project
        lead invite them to a single project as a client.
      </p>

      {queued > 0 && (
        <div
          style={{
            marginTop: 18,
            padding: '11px 13px',
            background: '#FDF8EE',
            border: '1px solid #EADDC2',
            borderRadius: 'var(--radius-field)',
            fontSize: 13.5,
            lineHeight: 1.5,
            color: '#8A6420',
          }}
        >
          <strong style={{ fontWeight: 600 }}>
            {queued} {queued === 1 ? 'email is' : 'emails are'} queued and unsent.
          </strong>{' '}
          No mail provider is wired yet, so nothing has actually been delivered — contact people
          directly until it is.
        </div>
      )}

      <div
        role="tablist"
        aria-label="Filter requests"
        style={{ display: 'flex', gap: 4, margin: '22px 0 16px', borderBottom: '1px solid var(--panel-border)' }}
      >
        {TABS.map((t) => {
          const active = t.key === tab
          return (
            <button
              key={t.key}
              role="tab"
              aria-selected={active}
              onClick={() => setTab(t.key)}
              style={{
                padding: '8px 12px',
                background: 'none',
                border: 'none',
                borderBottom: active ? '2px solid var(--accent)' : '2px solid transparent',
                marginBottom: -1,
                fontSize: 13.5,
                fontWeight: active ? 600 : 400,
                color: active ? 'var(--ink)' : 'var(--muted)',
                cursor: 'pointer',
              }}
            >
              {t.label}
            </button>
          )
        })}
      </div>

      {requests.isLoading ? (
        <p style={{ fontSize: 14, color: 'var(--muted)' }}>Loading…</p>
      ) : requests.isError ? (
        <p style={{ fontSize: 14, color: 'var(--error-text)' }}>
          Couldn&apos;t load requests. Try again in a moment.
        </p>
      ) : rows.length === 0 ? (
        <div style={{ ...CARD, textAlign: 'center', padding: '34px 18px' }}>
          <p style={{ margin: 0, fontSize: 14.5, color: 'var(--muted)' }}>
            {tab === 'pending' ? 'Nothing waiting on you.' : 'Nothing here.'}
          </p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
          {rows.map((r) => (
            <RequestCard key={r.id} request={r} />
          ))}
        </div>
      )}
    </div>
  )
}
