import { Link } from 'react-router'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/ui/tooltip'
import { VersionMenu } from './VersionMenu'
import { PublishDraftButton } from './PublishDraftButton'
import { DiscardDraftButton } from './DiscardDraftButton'
import type { AssetVersionRow } from './queries'
import type { AssetNeighborRow } from '@/features/designs/queries'
import { PresenceStack } from '@/features/realtime/PresenceStack'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  assetName: string
  activeVersion: AssetVersionRow | null
  versions: AssetVersionRow[]
  currentVersionId: string | null
  canSetCurrent: boolean
  canPublishVersion: boolean
  canDiscardVersion: boolean
  canCreateVersion: boolean
  neighbors: AssetNeighborRow[]
  scopeQuery?: string
}

export function VersionBar({
  workspaceId,
  projectId,
  assetId,
  assetName,
  activeVersion,
  versions,
  currentVersionId,
  canSetCurrent,
  canPublishVersion,
  canDiscardVersion,
  canCreateVersion,
  neighbors,
  scopeQuery,
}: Props) {
  const idx = neighbors.findIndex((n) => n.id === assetId)
  const prev = idx > 0 ? neighbors[idx - 1] : undefined
  const next = idx >= 0 && idx < neighbors.length - 1 ? neighbors[idx + 1] : undefined
  const suffix = scopeQuery ? `?${scopeQuery}` : ''
  const isDraftActive = activeVersion?.status === 'draft'

  return (
    <div className="flex items-center gap-2 border-b border-[--color-border] bg-[--color-surface] px-3 py-2">
      <NeighborButton
        target={prev}
        direction="prev"
        workspaceId={workspaceId}
        projectId={projectId}
        suffix={suffix}
      />
      <div className="flex min-w-0 flex-1 items-center gap-2">
        <h1 className="min-w-0 truncate text-sm font-semibold">{assetName}</h1>
        <VersionMenu
          workspaceId={workspaceId}
          projectId={projectId}
          assetId={assetId}
          assetName={assetName}
          activeVersion={activeVersion}
          versions={versions}
          currentVersionId={currentVersionId}
          canSetCurrent={canSetCurrent}
          canCreateVersion={canCreateVersion}
          scopeQuery={scopeQuery}
        />
      </div>
      <PresenceStack versionId={activeVersion?.id ?? null} />
      {isDraftActive && activeVersion && (
        <div className="flex items-center gap-1">
          {canDiscardVersion && (
            <DiscardDraftButton
              workspaceId={workspaceId}
              projectId={projectId}
              assetId={assetId}
              version={activeVersion}
              scopeQuery={scopeQuery}
            />
          )}
          {canPublishVersion && (
            <PublishDraftButton
              workspaceId={workspaceId}
              projectId={projectId}
              assetId={assetId}
              version={activeVersion}
              currentVersionId={currentVersionId}
              canSetCurrent={canSetCurrent}
            />
          )}
        </div>
      )}
      <NeighborButton
        target={next}
        direction="next"
        workspaceId={workspaceId}
        projectId={projectId}
        suffix={suffix}
      />
    </div>
  )
}

function NeighborButton({
  target,
  direction,
  workspaceId,
  projectId,
  suffix,
}: {
  target: AssetNeighborRow | undefined
  direction: 'prev' | 'next'
  workspaceId: string
  projectId: string
  suffix: string
}) {
  const Icon = direction === 'prev' ? ChevronLeft : ChevronRight
  const label = direction === 'prev' ? 'Previous asset' : 'Next asset'
  if (!target) {
    return (
      <Button variant="ghost" size="icon" aria-label={label} disabled>
        <Icon className="h-4 w-4" />
      </Button>
    )
  }
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button asChild variant="ghost" size="icon" aria-label={`${label}: ${target.name}`}>
          <Link
            to={`/workspace/${workspaceId}/project/${projectId}/asset/${target.id}${suffix}`}
          >
            <Icon className="h-4 w-4" />
          </Link>
        </Button>
      </TooltipTrigger>
      <TooltipContent>{target.name}</TooltipContent>
    </Tooltip>
  )
}
