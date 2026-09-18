import { useParams } from 'react-router'
import {
  FolderOpen,
  Users,
  Settings2,
  LayoutDashboard,
  Layers,
  ClipboardList,
  Rocket,
  UserRound,
  ClipboardCheck,
  Inbox,
} from 'lucide-react'
import { NavItem } from '@/shell/NavItem'
import { useReviewInboxCount } from '@/features/reviews/queries'
import { useNotificationBadgeCount } from '@/features/notifications/queries'
import { cn } from '@/lib/cn'

type Mode = 'workspace' | 'project'

interface Props {
  mode: Mode
  collapsed?: boolean
  onNavigate?: () => void
}

/**
 * The one left rail. Renders workspace-mode items or project-mode items.
 * Mode is caller-controlled (layouts pass it) rather than URL-derived so
 * layouts stay in control of context loading.
 */
export function NavRail({ mode, collapsed = false, onNavigate }: Props) {
  const { ws_id, proj_id } = useParams()
  const inbox = useReviewInboxCount(ws_id)
  const inboxBadge = inbox.data?.assigned_to_me ?? 0
  const notif = useNotificationBadgeCount(ws_id)
  const notifBadge = notif.data?.total_unread ?? 0

  return (
    <nav
      onClick={onNavigate}
      className={cn(
        'flex h-full flex-col gap-1 border-r border-[--color-border] bg-[--color-surface] p-2',
        collapsed ? 'w-16' : 'w-56',
      )}
      aria-label={mode === 'workspace' ? 'Workspace navigation' : 'Project navigation'}
    >
      {mode === 'workspace' && ws_id && (
        <>
          <NavItem
            to={`/workspace/${ws_id}/projects`}
            label="Projects"
            icon={<FolderOpen />}
            collapsed={collapsed}
          />
          <NavItem
            to={`/workspace/${ws_id}/inbox`}
            label="Inbox"
            icon={<Inbox />}
            collapsed={collapsed}
            badge={notifBadge > 0 ? (notifBadge > 99 ? '99+' : String(notifBadge)) : undefined}
          />
          <NavItem
            to={`/workspace/${ws_id}/reviews`}
            label="Reviews"
            icon={<ClipboardCheck />}
            collapsed={collapsed}
            badge={inboxBadge > 0 ? (inboxBadge > 99 ? '99+' : String(inboxBadge)) : undefined}
          />
          <NavItem
            to={`/workspace/${ws_id}/people`}
            label="People"
            icon={<Users />}
            collapsed={collapsed}
          />
          <NavItem
            to={`/workspace/${ws_id}/settings`}
            label="Settings"
            icon={<Settings2 />}
            collapsed={collapsed}
          />
        </>
      )}

      {mode === 'project' && ws_id && proj_id && (
        <>
          <NavItem
            to={`/workspace/${ws_id}/project/${proj_id}/overview`}
            label="Overview"
            icon={<LayoutDashboard />}
            collapsed={collapsed}
            capability="project.view"
          />
          <NavItem
            to={`/workspace/${ws_id}/project/${proj_id}/designs`}
            label="Designs"
            icon={<Layers />}
            collapsed={collapsed}
            capability="asset.view"
          />
          <NavItem
            to={`/workspace/${ws_id}/project/${proj_id}/reviews`}
            label="Reviews"
            icon={<ClipboardCheck />}
            collapsed={collapsed}
            capability="review.view"
          />
          <NavItem
            to={`/workspace/${ws_id}/project/${proj_id}/requirements`}
            label="Requirements"
            icon={<ClipboardList />}
            collapsed={collapsed}
            capability="requirement.view"
          />
          <NavItem
            to={`/workspace/${ws_id}/project/${proj_id}/releases`}
            label="Releases"
            icon={<Rocket />}
            collapsed={collapsed}
            capability="release.view"
          />
          <NavItem
            to={`/workspace/${ws_id}/project/${proj_id}/people`}
            label="People"
            icon={<UserRound />}
            collapsed={collapsed}
            capability="project.view"
          />
        </>
      )}
    </nav>
  )
}
