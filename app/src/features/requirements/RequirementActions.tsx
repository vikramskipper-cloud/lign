import { Archive, Bookmark, BookmarkPlus, Link2, MoreHorizontal } from 'lucide-react'
import { Button } from '@/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/ui/dropdown-menu'
import { useCopyLink } from '@/features/comments/useCopyLink'
import { useArchiveRequirement, useToggleRequirementBookmark } from './mutations'
import type { CapabilityMap } from '@/types/capabilities'

interface Props {
  workspaceId: string
  projectId: string
  requirementId: string
  code: string
  status: 'draft' | 'active' | 'superseded' | 'archived'
  caps: CapabilityMap | null | undefined
  isBookmarked: boolean
}

export function RequirementActions({
  workspaceId,
  projectId,
  requirementId,
  code,
  status,
  caps,
  isBookmarked,
}: Props) {
  const copy = useCopyLink()
  const archive = useArchiveRequirement(workspaceId, projectId)
  const bookmark = useToggleRequirementBookmark(workspaceId)

  const canArchive =
    Boolean(caps?.['requirement.archive']) && status !== 'archived' &&
    status !== 'superseded'

  return (
    <div className="flex items-center gap-1">
      <Button
        variant="secondary"
        size="sm"
        onClick={() => bookmark.mutate({ subjectId: requirementId })}
        title={isBookmarked ? 'Remove bookmark' : 'Bookmark'}
      >
        {isBookmarked ? (
          <Bookmark className="h-4 w-4" />
        ) : (
          <BookmarkPlus className="h-4 w-4" />
        )}
      </Button>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="secondary" size="sm" aria-label="More actions">
            <MoreHorizontal className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-[12rem]">
          <DropdownMenuItem
            onSelect={() => copy('requirement', requirementId)}
          >
            <Link2 className="mr-2 h-3.5 w-3.5" />
            Copy link
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() => {
              void navigator.clipboard?.writeText(code)
            }}
          >
            <Link2 className="mr-2 h-3.5 w-3.5" />
            Copy code ({code})
          </DropdownMenuItem>
          {canArchive && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onSelect={() => {
                  if (confirm(`Archive ${code}?`)) {
                    archive.mutate(requirementId)
                  }
                }}
              >
                <Archive className="mr-2 h-3.5 w-3.5" />
                Archive
              </DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  )
}
