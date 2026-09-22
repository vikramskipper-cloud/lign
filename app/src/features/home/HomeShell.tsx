import * as React from 'react'
import { Link, useLocation, useNavigate } from 'react-router'
import {
  Bell, ChevronDown, ClipboardCheck, ClipboardList, FolderOpen, Home, Inbox,
  Menu, Rocket, Search, Settings2, Stamp, Users,
} from 'lucide-react'
import { useSession } from '@/auth/SessionProvider'
import { useWorkspaces } from '@/shell/queries'
import { useWorkspaceAccess } from '@/lib/capabilities'
import { useNotificationBadgeCount } from '@/features/notifications/queries'
import { useReviewInboxCount } from '@/features/reviews/queries'
import { Wordmark } from '@/auth/AuthShell'
import { PINNED_CAP } from './copy'
import '@/styles/auth-theme.css'

/**
 * Home's own chrome.
 *
 * Deliberately NOT RootLayout. The brief specifies a different top bar and
 * sidebar from APP 002's TopBar/NavRail, so Home is routed outside that
 * layout. Consequence, flagged: two navigation systems coexist until the
 * redesign reaches the rest of the app.
 */

export interface PinnedProject {
  id: string
  name: string
  dot: string
}

interface Props {
  workspaceId: string
  projectCount: number
  pinned: PinnedProject[]
  children: React.ReactNode
}

export function HomeShell({ workspaceId, projectCount, pinned, children }: Props) {
  const { user, signOut } = useSession()
  const navigate = useNavigate()
  const workspaces = useWorkspaces()
  const access = useWorkspaceAccess(workspaceId)
  const badge = useNotificationBadgeCount(workspaceId)
  const reviewInbox = useReviewInboxCount(workspaceId)
  const { pathname } = useLocation()

  const [wsMenuOpen, setWsMenuOpen] = React.useState(false)
  const [userMenuOpen, setUserMenuOpen] = React.useState(false)
  const [navOpen, setNavOpen] = React.useState(false)

  const all = workspaces.data ?? []
  const current = all.find((w) => w.id === workspaceId)
  // Workspace is the tenant boundary, not a navigation level: with one
  // workspace it is identity, so it renders as a label with no affordance.
  const canSwitch = all.length > 1

  const canSeePeople = Boolean(access.data?.['member.invite'] || access.data?.['workspace.manage'])
  const canSeeSettings = Boolean(access.data?.['workspace.manage'])
  const unread = badge.data?.total_unread ?? 0
  const myReviews = reviewInbox.data?.assigned_to_me ?? 0

  const ws = (path: string) => `/workspace/${workspaceId}/${path}`

  /** Count pill. Capped at 99+ so a busy workspace cannot widen the rail. */
  const count = (n: number, tone: 'accent' | 'quiet' = 'quiet') =>
    n > 0 ? (
      <span
        className="auth-mono"
        style={{
          fontSize: 10.5, lineHeight: '16px', minWidth: 16, padding: '0 5px',
          borderRadius: 8, textAlign: 'center',
          color: tone === 'accent' ? '#fff' : 'var(--faint)',
          background: tone === 'accent' ? 'var(--accent)' : 'transparent',
        }}
      >
        {n > 99 ? '99+' : n}
      </span>
    ) : undefined

  const navItem = (to: string, label: string, icon: React.ReactNode, trailing?: React.ReactNode) => {
    const active = pathname === to || pathname.startsWith(`${to}/`)
    return (
    <Link
      to={to}
      onClick={() => setNavOpen(false)}
      aria-current={active ? 'page' : undefined}
      style={{
        display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px',
        borderRadius: 8, textDecoration: 'none', minHeight: 36,
        background: active ? 'var(--surface)' : 'transparent',
        color: active ? 'var(--ink)' : 'var(--text)',
        fontSize: 13.5, fontWeight: active ? 500 : 400,
      }}
    >
      <span aria-hidden="true" style={{ display: 'grid', placeItems: 'center', width: 16 }}>{icon}</span>
      <span style={{ flex: 1 }}>{label}</span>
      {trailing}
    </Link>
    )
  }

  const sidebar = (variant: 'home-sidebar' | 'home-drawer-nav') => (
    <nav className={`home-nav ${variant}`} aria-label="Main">
      {/* The full workspace route set, matching NavRail rather than a subset
          of it — an item missing here reads as a feature that does not exist.
          Deliberately ungated, as NavRail has always been: reviews, approvals,
          requirements and releases are project-scoped capabilities, and
          lign_has_capability cannot answer those with p_project_id = null. The
          screens enforce access; hiding them from a workspace admin, who does
          hold the read keys everywhere, would be the worse error. */}
      {navItem('/dashboard', 'Home', <Home size={15} />)}
      {navItem(ws('inbox'), 'Inbox', <Inbox size={15} />, count(unread, 'accent'))}
      {navItem(ws('projects'), 'Projects', <FolderOpen size={15} />, count(projectCount))}
      {navItem(ws('reviews'), 'Reviews', <ClipboardCheck size={15} />, count(myReviews, 'accent'))}
      {navItem(ws('approvals'), 'Approvals', <Stamp size={15} />)}
      {navItem(ws('requirements'), 'Requirements', <ClipboardList size={15} />)}
      {navItem(ws('releases'), 'Releases', <Rocket size={15} />)}

      {(canSeePeople || canSeeSettings) && (
        <div aria-hidden="true" style={{ height: 1, background: 'var(--panel-border)', margin: '10px 10px 9px' }} />
      )}
      {canSeePeople && navItem(ws('people'), 'People', <Users size={15} />)}
      {canSeeSettings && navItem(ws('settings'), 'Settings', <Settings2 size={15} />)}

      {pinned.length > 0 && (
        <>
          <p className="auth-mono" style={{ margin: '18px 0 6px 10px', fontSize: 10.5, letterSpacing: '0.12em', color: 'var(--faint)' }}>
            PINNED
          </p>
          {pinned.slice(0, PINNED_CAP).map((p) => (
            <Link
              key={p.id}
              to={`/workspace/${workspaceId}/project/${p.id}/overview`}
              onClick={() => setNavOpen(false)}
              style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '7px 10px', borderRadius: 8, textDecoration: 'none', color: 'var(--text)', fontSize: 13, minHeight: 34 }}
            >
              <span aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', background: p.dot, flex: '0 0 7px' }} />
              <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.name}</span>
            </Link>
          ))}
        </>
      )}
    </nav>
  )

  return (
    <div className="lign-warm" style={{ minHeight: '100dvh', display: 'flex', flexDirection: 'column' }}>
      <header
        style={{
          height: 56, flex: '0 0 56px', background: 'var(--surface)',
          borderBottom: '1px solid var(--border-soft)', display: 'flex',
          alignItems: 'center', gap: 12, padding: '0 16px',
        }}
      >
        <button
          type="button"
          className="home-nav-toggle"
          aria-label="Open navigation"
          aria-expanded={navOpen}
          onClick={() => setNavOpen((v) => !v)}
          style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--muted)', padding: 8, minHeight: 44, minWidth: 44 }}
        >
          <Menu size={18} />
        </button>

        <Wordmark />

        <div style={{ position: 'relative' }}>
          {canSwitch ? (
            <button
              type="button"
              onClick={() => setWsMenuOpen((v) => !v)}
              aria-expanded={wsMenuOpen}
              aria-haspopup="menu"
              style={{ display: 'flex', alignItems: 'center', gap: 5, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text)', fontSize: 13.5, padding: '6px 8px', borderRadius: 7, minHeight: 36 }}
            >
              {current?.name ?? 'Workspace'}
              <ChevronDown size={14} aria-hidden="true" />
            </button>
          ) : (
            <span style={{ fontSize: 13.5, color: 'var(--text)', padding: '6px 8px' }}>
              {current?.name ?? 'Workspace'}
            </span>
          )}
          {wsMenuOpen && canSwitch && (
            <div
              role="menu"
              style={{ position: 'absolute', top: '100%', left: 0, marginTop: 4, minWidth: 200, background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 10, padding: 4, zIndex: 40, boxShadow: '0 8px 24px -12px rgba(0,0,0,.25)' }}
            >
              {all.map((w) => (
                <button
                  key={w.id}
                  role="menuitem"
                  onClick={() => {
                    setWsMenuOpen(false)
                    // Persisted as last-used by the same helper the rest of the
                    // app reads, so Home and WorkspaceSwitcher agree.
                    try { window.localStorage.setItem('lign.lastWorkspaceId', w.id) } catch { /* ignore */ }
                    navigate(`/dashboard?ws=${w.id}`, { replace: true })
                  }}
                  style={{ display: 'block', width: '100%', textAlign: 'left', padding: '8px 10px', background: w.id === workspaceId ? 'var(--panel)' : 'none', border: 'none', borderRadius: 7, cursor: 'pointer', fontSize: 13.5, color: 'var(--text)', minHeight: 36 }}
                >
                  {w.name}
                </button>
              ))}
            </div>
          )}
        </div>

        <div style={{ flex: 1 }} />

        {/* TODO: wire to the search surface when one exists — out of scope here. */}
        <label className="home-search" style={{ position: 'relative', width: 280 }}>
          <span className="sr-only" style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }}>
            Search
          </span>
          <Search size={14} aria-hidden="true" style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--faint)' }} />
          <input
            className="auth-field"
            placeholder="Search projects, assets, releases"
            style={{ height: 34, fontSize: 13, paddingLeft: 30 }}
          />
        </label>

        <Link
          to={`/workspace/${workspaceId}/inbox`}
          aria-label={unread > 0 ? `Notifications, ${unread} unread` : 'Notifications'}
          style={{ position: 'relative', display: 'grid', placeItems: 'center', width: 44, height: 44, color: 'var(--muted)' }}
        >
          <Bell size={17} aria-hidden="true" />
          {unread > 0 && (
            <span aria-hidden="true" style={{ position: 'absolute', top: 10, right: 11, width: 7, height: 7, borderRadius: '50%', background: 'var(--accent)' }} />
          )}
        </Link>

        <div style={{ position: 'relative' }}>
          <button
            type="button"
            onClick={() => setUserMenuOpen((v) => !v)}
            aria-expanded={userMenuOpen}
            aria-haspopup="menu"
            aria-label="Account menu"
            style={{ width: 44, height: 44, display: 'grid', placeItems: 'center', background: 'none', border: 'none', cursor: 'pointer' }}
          >
            <span style={{ width: 28, height: 28, borderRadius: '50%', background: 'var(--panel)', border: '1px solid var(--panel-border)', display: 'grid', placeItems: 'center', fontSize: 11.5, fontWeight: 600, color: 'var(--ink)' }}>
              {(user?.email ?? '?').slice(0, 2).toUpperCase()}
            </span>
          </button>
          {userMenuOpen && (
            <div role="menu" style={{ position: 'absolute', top: '100%', right: 0, marginTop: 4, minWidth: 200, background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 10, padding: 4, zIndex: 40, boxShadow: '0 8px 24px -12px rgba(0,0,0,.25)' }}>
              <p style={{ margin: 0, padding: '8px 10px', fontSize: 12.5, color: 'var(--muted)', wordBreak: 'break-all' }}>{user?.email}</p>
              <button
                role="menuitem"
                onClick={async () => { await signOut(); navigate('/sign-in', { replace: true }) }}
                style={{ display: 'block', width: '100%', textAlign: 'left', padding: '8px 10px', background: 'none', border: 'none', borderRadius: 7, cursor: 'pointer', fontSize: 13.5, color: 'var(--text)', minHeight: 40 }}
              >
                Sign out
              </button>
            </div>
          )}
        </div>
      </header>

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {sidebar('home-sidebar')}
        {navOpen && (
          // Backdrop closes; the rail inside it does not.
          <div className="home-drawer" onClick={() => setNavOpen(false)}>
            <div onClick={(e) => e.stopPropagation()} style={{ display: 'contents' }}>
              {sidebar('home-drawer-nav')}
            </div>
          </div>
        )}
        <main style={{ flex: 1, minWidth: 0, overflow: 'auto' }}>{children}</main>
      </div>
    </div>
  )
}
