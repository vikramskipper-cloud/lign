import { Avatar, AvatarFallback } from '@/ui/avatar'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/ui/tooltip'
import { cn } from '@/lib/cn'
import { useVersionPresence } from './usePresence'

function initials(email: string): string {
  const local = email.split('@')[0] ?? ''
  return local.slice(0, 2).toUpperCase() || '?'
}

const MAX_SHOWN = 3

/**
 * APP 011 wave 2 — stacked avatars of other people viewing this version.
 * Renders nothing when nobody else is here, so the bar is unchanged in the
 * common single-viewer case.
 */
export function PresenceStack({ versionId }: { versionId: string | null }) {
  const peers = useVersionPresence(versionId)
  if (peers.length === 0) return null

  const shown = peers.slice(0, MAX_SHOWN)
  const overflow = peers.length - shown.length
  const label =
    peers.length === 1
      ? `${peers[0].email} is also viewing this version`
      : `${peers.length} others viewing: ${peers.map((p) => p.email).join(', ')}`

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <div className="flex items-center -space-x-2" role="group" aria-label={label}>
          {shown.map((p) => (
            <Avatar key={p.profileId} className="h-6 w-6 ring-2 ring-[--color-surface]">
              <AvatarFallback className="text-[10px]">{initials(p.email)}</AvatarFallback>
            </Avatar>
          ))}
          {overflow > 0 && (
            <span
              className={cn(
                'grid h-6 w-6 place-items-center rounded-full ring-2 ring-[--color-surface]',
                'bg-[--color-surface-2] text-[10px] font-medium text-[--color-text-muted]',
              )}
            >
              +{overflow}
            </span>
          )}
        </div>
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  )
}
