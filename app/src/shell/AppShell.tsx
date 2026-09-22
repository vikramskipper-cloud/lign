import * as React from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router'
import {
  ChevronDown, ClipboardCheck, ClipboardList, FolderOpen, Home, Inbox, Layers,
  LayoutDashboard, Menu, Rocket, Search, Settings2, Stamp, UserRound, Users,
} from 'lucide-react'
import { useWorkspaces, useProject } from '@/shell/queries'
import { useActiveWorkspaceId } from '@/shell/useActiveWorkspace'
import { useWorkspaceAccess, useProjectCapabilities } from '@/lib/capabilities'
import { useNotificationBadgeCount } from '@/features/notifications/queries'
import { useReviewInboxCount } from '@/features/reviews/queries'
import { NotificationBell } from '@/features/notifications/NotificationBell'
import { RealtimeIndicator } from '@/features/realtime/RealtimeIndicator'
import { UserMenu } from '@/shell/UserMenu'
import { Breadcrumb } from '@/shell/Breadcrumb'
import { usePinnedProjectIds } from '@/features/home/pins'
import { useMyParticipations } from '@/features/home/queries'
import { PINNED_CAP } from '@/features/home/copy'
import { Wordmark } from '@/auth/AuthShell'
import type { CapabilityKey } from '@/types/capabilities'
import '@/styles/auth-theme.css'

/**
 * The one chrome: warm top bar + left rail, wrapped around every
 * authenticated route.
 *
 * This replaces APP 002's TopBar + NavRail. Those rendered a zinc-themed bar
 * and a rail that SWAPPED between workspace items and project items depending
 * on where you were, so entering a project made the workspace navigation
 * disappear. Here the workspace rail is constant and the project section is
 * added below it, which is what "constant chrome" has to mean in practice:
 * the same furniture in the same place on every page.
 *
 * The bell, realtime indicator and user menu are the existing components
 * rather than warm re-skins. They carry real behaviour — the notification
 * centre popover, the N hotkey, connection state — and re-implementing that
 * to match a palette would be trading function for finish. They are icon
 * buttons either way. Flagged as the remaining visual seam.
 */

interface NavEntry {
  to: string
  label: string
  icon: React.ReactNode
  trailing?: React.ReactNode
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const { proj_id } = useParams<{ proj_id?: string }>()
  const navigate = useNavigate()
  const { pathname } = useLocation()

  const { workspaceId } = useActiveWorkspaceId()
  const workspaces = useWorkspaces()
  const access = useWorkspaceAccess(workspaceId)
  const badge = useNotificationBadgeCount(workspaceId)
  const reviewInbox = useReviewInboxCount(workspaceId)
  const parts = useMyParticipations(workspaceId)
  const pins = usePinnedProjectIds(workspaceId)
  const project = useProject(proj_id)
  // Already fetched by ProjectLayout under the same key — this is a cache read,
  // not a second round of lign_has_capability calls.
  const projectCaps = useProjectCapabilities(proj_id ?? '', workspaceId ?? '')

  const [wsMenuOpen, setWsMenuOpen] = React.useState(false)
  const [navOpen, setNavOpen] = React.useState(false)

  // Any navigation closes the mobile drawer. Doing it here rather than on each
  // link covers the ways out that are not links: the workspace switcher, the
  // notification centre, a redirect from a layout guard.
  React.useEffect(() => { setNavOpen(false) }, [pathname])

  const all = workspaces.data ?? []
  const current = all.find((w) => w.id === workspaceId)
  // Workspace is the tenant boundary, not a navigation level: with one
  // workspace it is identity, so it renders as a label with no affordance.
  const canSwitch = all.length > 1

  const canSeePeople = Boolean(access.data?.['member.invite'] || access.data?.['workspace.manage'])
  const canSeeSettings = Boolean(access.data?.['workspace.manage'])
  const unread = badge.data?.total_unread ?? 0
  const myReviews = reviewInbox.data?.assigned_to_me ?? 0
  const participations = parts.data ?? []

  const ws = (path: string) => `/workspace/${workspaceId}/${path}`
  const proj = (path: string) => `/workspace/${workspaceId}/project/${proj_id}/${path}`

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

  const navItem = ({ to, label, icon, trailing }: NavEntry) => {
    const active = pathname === to || pathname.startsWith(`${to}/`)
    return (
      <Link
        key={to}
        to={to}
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
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
        {trailing}
      </Link>
    )
  }

  const groupLabel = (text: string) => (
    <p
      className="auth-mono"
      style={{ margin: '18px 0 6px 10px', fontSize: 10.5, letterSpacing: '0.12em', color: 'var(--faint)' }}
    >
      {text}
    </p>
  )

  /**
   * Workspace destinations are deliberately NOT capability-gated, as NavRail
   * was not: reviews, approvals, requirements and releases are project-scoped
   * keys, and lign_has_capability cannot answer those with p_project_id =
   * null. The screens enforce access. Hiding them from a workspace admin, who
   * holds the read keys on every project, would be the worse error.
   */
  const workspaceNav: NavEntry[] = [
    { to: '/dashboard', label: 'Home', icon: <Home size={15} /> },
    { to: ws('inbox'), label: 'Inbox', icon: <Inbox size={15} />, trailing: count(unread, 'accent') },
    { to: ws('projects'), label: 'Projects', icon: <FolderOpen size={15} />, trailing: count(participations.length) },
    { to: ws('reviews'), label: 'Reviews', icon: <ClipboardCheck size={15} />, trailing: count(myReviews, 'accent') },
    { to: ws('approvals'), label: 'Approvals', icon: <Stamp size={15} /> },
    { to: ws('requirements'), label: 'Requirements', icon: <ClipboardList size={15} /> },
    { to: ws('releases'), label: 'Releases', icon: <Rocket size={15} /> },
  ]

  // Project destinations DO gate, because here there is a project in scope and
  // so the capability map is answerable. Same keys NavRail used.
  const projectNav: Array<NavEntry & { capability: CapabilityKey }> = [
    { to: proj('overview'), label: 'Overview', icon: <LayoutDashboard size={15} />, capability: 'project.view' },
    { to: proj('designs'), label: 'Designs', icon: <Layers size={15} />, capability: 'asset.view' },
    { to: proj('reviews'), label: 'Reviews', icon: <ClipboardCheck size={15} />, capability: 'review.view' },
    { to: proj('requirements'), label: 'Requirements', icon: <ClipboardList size={15} />, capability: 'requirement.view' },
    { to: proj('releases'), label: 'Releases', icon: <Rocket size={15} />, capability: 'release.view' },
    { to: proj('people'), label: 'People', icon: <UserRound size={15} />, capability: 'project.view' },
  ]

  const pinned = (pins.data ?? [])
    .map((id) => participations.find((p) => p.projectId === id))
    .filter(Boolean)
    .slice(0, PINNED_CAP)

  const sidebar = (variant: 'app-sidebar' | 'app-drawer-nav') => (
    <nav className={`app-nav ${variant}`} aria-label="Main">
      {workspaceNav.map(navItem)}

      {(canSeePeople || canSeeSettings) && (
        <div aria-hidden="true" style={{ height: 1, background: 'var(--panel-border)', margin: '10px 10px 9px' }} />
      )}
      {canSeePeople && navItem({ to: ws('people'), label: 'People', icon: <Users size={15} /> })}
      {canSeeSettings && navItem({ to: ws('settings'), label: 'Settings', icon: <Settings2 size={15} /> })}

      {proj_id && (
        <>
          {groupLabel((project.data?.name ?? 'Project').toUpperCase())}
          {projectNav
            .filter((e) => projectCaps.data?.[e.capability])
            .map(navItem)}
        </>
      )}

      {pinned.length > 0 && (
        <>
          {groupLabel('PINNED')}
          {pinned.map((p) => (
            <Link
              key={p!.projectId}
              to={`/workspace/${workspaceId}/project/${p!.projectId}/overview`}
              style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '7px 10px', borderRadius: 8, textDecoration: 'none', color: 'var(--text)', fontSize: 13, minHeight: 34 }}
            >
              <span aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--status-superseded)', flex: '0 0 7px' }} />
              <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p!.projectName}</span>
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
          className="app-nav-toggle"
          aria-label="Open navigation"
          aria-expanded={navOpen}
          onClick={() => setNavOpen((v) => !v)}
          style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--muted)', padding: 8, minHeight: 44, minWidth: 44 }}
        >
          <Menu size={18} />
        </button>

        <Link to="/dashboard" aria-label="Home" style={{ textDecoration: 'none', flex: '0 0 auto' }}>
          <Wordmark />
        </Link>

        <div style={{ position: 'relative', flex: '0 0 auto' }}>
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
                    // From the dashboard, stay on the dashboard — it is
                    // workspace-agnostic, so re-scoping it is the whole
                    // intent. From anywhere else, go to the new workspace's
                    // projects: the record you were looking at does not exist
                    // in the workspace you just switched to.
                    navigate(
                      pathname === '/dashboard'
                        ? `/dashboard?ws=${w.id}`
                        : `/workspace/${w.id}/projects`,
                    )
                  }}
                  style={{ display: 'block', width: '100%', textAlign: 'left', padding: '8px 10px', background: w.id === workspaceId ? 'var(--panel)' : 'none', border: 'none', borderRadius: 7, cursor: 'pointer', fontSize: 13.5, color: 'var(--text)', minHeight: 36 }}
                >
                  {w.name}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Project › page. The workspace segment is suppressed because the
            switcher to the left already is it. */}
        <div className="app-crumb" style={{ minWidth: 0, flex: 1 }}>
          <Breadcrumb compact />
        </div>

        {/* TODO: wire to the search surface when one exists — out of scope here. */}
        <label className="app-search" style={{ position: 'relative', width: 240, flex: '0 0 auto' }}>
          <span style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }}>
            Search
          </span>
          <Search size={14} aria-hidden="true" style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--faint)' }} />
          <input
            className="auth-field"
            placeholder="Search projects, assets, releases"
            style={{ height: 34, fontSize: 13, paddingLeft: 30 }}
          />
        </label>

        <RealtimeIndicator />
        <NotificationBell />
        <UserMenu />
      </header>

      <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
        {workspaceId && sidebar('app-sidebar')}
        {workspaceId && navOpen && (
          // Backdrop closes; the rail inside it does not.
          <div className="app-drawer" onClick={() => setNavOpen(false)}>
            <div onClick={(e) => e.stopPropagation()} style={{ display: 'contents' }}>
              {sidebar('app-drawer-nav')}
            </div>
          </div>
        )}
        <main style={{ flex: 1, minWidth: 0, overflow: 'auto' }}>{children}</main>
      </div>
    </div>
  )
}
