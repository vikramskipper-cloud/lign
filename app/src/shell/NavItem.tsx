import * as React from 'react'
import { NavLink } from 'react-router'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/ui/tooltip'
import { cn } from '@/lib/cn'
import type { CapabilityKey } from '@/types/capabilities'
import { useCapability } from '@/lib/capabilities'
import { useParams } from 'react-router'

interface NavItemProps {
  to: string
  label: string
  icon: React.ReactNode
  end?: boolean
  /** If provided, the item is hidden when the capability check is false. */
  capability?: CapabilityKey
  /** When true, only render the icon (collapsed rail / tablet). */
  collapsed?: boolean
  /** Optional badge string (e.g. inbox count). */
  badge?: string
}

/**
 * Single left-rail item. Uses NavLink for the active style. Hidden entirely
 * when a capability is provided and the caller doesn't have it.
 */
export function NavItem({ to, label, icon, end, capability, collapsed, badge }: NavItemProps) {
  const { proj_id, ws_id } = useParams()
  const allowed = useCapability(proj_id, ws_id, capability!)

  if (capability && !allowed) return null

  const link = (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        cn(
          'group flex h-9 items-center gap-3 rounded-[--radius-md] px-3 text-sm font-medium transition-colors',
          collapsed && 'justify-center px-0',
          isActive
            ? 'bg-[--color-surface-2] text-[--color-text]'
            : 'text-[--color-text-muted] hover:bg-[--color-surface-2] hover:text-[--color-text]',
        )
      }
    >
      <span className="relative [&_svg]:h-4 [&_svg]:w-4">
        {icon}
        {collapsed && badge && (
          <span className="absolute -right-2 -top-1 min-w-[16px] rounded-full bg-[--color-state-open] px-1 text-center text-[9px] font-semibold text-[--color-brand-fg]">
            {badge}
          </span>
        )}
      </span>
      {!collapsed && (
        <>
          <span className="flex-1 truncate">{label}</span>
          {badge && (
            <span className="min-w-[18px] rounded-full bg-[--color-state-open] px-1.5 text-center text-[10px] font-semibold text-[--color-brand-fg]">
              {badge}
            </span>
          )}
        </>
      )}
    </NavLink>
  )

  if (collapsed) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>{link}</TooltipTrigger>
        <TooltipContent side="right">{label}</TooltipContent>
      </Tooltip>
    )
  }
  return link
}
