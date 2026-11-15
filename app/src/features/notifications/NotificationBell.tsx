import { useEffect } from 'react'
import { Link, useNavigate } from 'react-router'
import { Bell } from 'lucide-react'
import { useNavigationContext } from '@/shell/navigationContext'
import { useOrganizationBadge } from './organizationQueries'

/** The global bell and sidebar Inbox always use the same organisation scope. */
export function NotificationBell() {
  const { organizationId } = useNavigationContext()
  const query = useOrganizationBadge(organizationId)
  const navigate = useNavigate()
  const to = organizationId ? `/org/${organizationId}/inbox` : '/my-work'
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (event.key.toLowerCase() !== 'n' || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return
      const target = event.target
      if (target instanceof HTMLElement && (['INPUT','TEXTAREA','SELECT'].includes(target.tagName) || target.isContentEditable)) return
      event.preventDefault(); navigate(to)
    }
    window.addEventListener('keydown',handler)
    return () => window.removeEventListener('keydown',handler)
  }, [to,navigate])
  return <Link to={to} className="relative inline-flex h-9 w-9 items-center justify-center rounded-md" aria-label={`Notifications (${query.data ?? 0} unread)`}><Bell size={17}/>{Boolean(query.data)&&<span className="absolute -right-1 -top-1 rounded-full bg-[#c54b20] px-1 text-[10px] text-white">{Math.min(query.data!,99)}</span>}</Link>
}
