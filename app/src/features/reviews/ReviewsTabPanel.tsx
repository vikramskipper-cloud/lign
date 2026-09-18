import * as React from 'react'
import { Link } from 'react-router'
import { Plus, ClipboardCheck } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative } from '@/lib/formatDate'
import { useReviewsForVersion } from './queries'
import { CreateReviewDialog } from './CreateReviewDialog'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string | null
  versionIsPublished: boolean
  canCreate: boolean
}

/**
 * Body of the RightPanel "Reviews" tab in the Design Workspace.
 * Lists reviews on the current version + a "Start review" affordance.
 * Additive to APP 005 (which reserved the tab as disabled).
 */
export function ReviewsTabPanel({
  workspaceId,
  projectId,
  assetId,
  versionId,
  versionIsPublished,
  canCreate,
}: Props) {
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const q = useReviewsForVersion(versionId ?? undefined)

  if (!versionId) {
    return <div className="p-3 text-sm text-[--color-text-muted]">No version selected.</div>
  }

  const rows = q.data ?? []
  const canStart = canCreate && versionIsPublished

  return (
    <div className="flex flex-col gap-2 p-3">
      {canStart ? (
        <Button size="sm" onClick={() => setDialogOpen(true)}>
          <Plus className="mr-1 h-3.5 w-3.5" />
          Start review on this version
        </Button>
      ) : canCreate && !versionIsPublished ? (
        <p className="rounded-[--radius-sm] border border-dashed border-[--color-border] p-2 text-xs text-[--color-text-subtle]">
          Publish this version to start a review.
        </p>
      ) : null}

      {q.isLoading ? (
        <p className="text-xs text-[--color-text-muted]">Loading…</p>
      ) : rows.length === 0 ? (
        <EmptyState
          icon={<ClipboardCheck className="h-6 w-6" />}
          title="No reviews on this version"
          description={canStart ? 'Start one above.' : undefined}
          className="mx-0"
        />
      ) : (
        <ul className="space-y-1.5">
          {rows.map((r) => (
            <li key={r.id}>
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/review/${r.id}`}
                className="block rounded-[--radius-sm] border border-transparent p-2 hover:border-[--color-border] hover:bg-[--color-surface-2]"
              >
                <div className="flex items-center gap-2">
                  <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] text-[--color-text-muted]">
                    R{r.round_number}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">{r.title}</span>
                  <StateBadge state={r.status as WorkflowState} />
                </div>
                {r.due_at && (
                  <p className="mt-0.5 text-[10px] text-[--color-text-subtle]">
                    due {relative(r.due_at)}
                  </p>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}

      {versionId && (
        <CreateReviewDialog
          workspaceId={workspaceId}
          projectId={projectId}
          designAssetId={assetId}
          versionId={versionId}
          open={dialogOpen}
          onOpenChange={setDialogOpen}
        />
      )}
    </div>
  )
}
