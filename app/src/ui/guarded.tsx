import * as React from 'react'
import { useParams } from 'react-router'
import { useCapability } from '@/lib/capabilities'
import type { CapabilityKey } from '@/types/capabilities'
import { AccessDeniedPage } from '@/shell/AccessDenied'

interface GuardedProps {
  capability: CapabilityKey
  /** How to render when the capability is missing. */
  fallback?: 'hide' | 'disabled' | 'route-block' | React.ReactNode
  children: React.ReactNode
}

/**
 * Permission-aware wrapper for actions and route elements.
 *
 * - `hide` (default): render nothing when the capability is missing.
 * - `disabled`: render children with disabled semantics (via [data-disabled]).
 * - `route-block`: render the AccessDenied page (for whole-route guarding).
 * - custom node: render that node as the fallback.
 *
 * The capability comes from the current URL's project/workspace params. Route
 * elements that use this MUST be mounted under ProjectLayout so params exist.
 */
export function Guarded({ capability, fallback = 'hide', children }: GuardedProps) {
  const { proj_id, ws_id } = useParams()
  const allowed = useCapability(proj_id, ws_id, capability)

  if (allowed) return <>{children}</>

  if (fallback === 'hide') return null
  if (fallback === 'route-block') return <AccessDeniedPage capability={capability} />
  if (fallback === 'disabled') {
    return (
      <div data-disabled="true" aria-disabled className="pointer-events-none opacity-50">
        {children}
      </div>
    )
  }
  return <>{fallback}</>
}
