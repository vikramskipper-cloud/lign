import * as React from 'react'
import { Link } from 'react-router'
import { Plus, ShieldCheck } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative } from '@/lib/formatDate'
import { useApprovalsForVersion } from './queries'
import { CreateApprovalDialog } from './CreateApprovalDialog'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string | null
  versionIsPublished: boolean
  canCreate: boolean
}

/**
 * RightPanel "Approvals" tab body for the Design Workspace.
 * Lists approvals on the current version + "Start approval" affordance.
 * Additive to APP 006 (reviews tab) and APP 005.
 */
export function ApprovalsTabPanel({
  workspaceId,
  projectId,
  assetId,
  versionId,
  versionIsPublished,
  canCreate,
}: Props) {
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const q = useApprovalsForVersion(versionId ?? undefined)

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
          Request approval on this version
        </Button>
      ) : canCreate && !versionIsPublished ? (
        <p className="rounded-[--radius-sm] border border-dashed border-[--color-border] p-2 text-xs text-[--color-text-subtle]">
          Publish this version to request an approval.
        </p>
      ) : null}

      {q.isLoading ? (
        <p className="text-xs text-[--color-text-muted]">Loading…</p>
      ) : rows.length === 0 ? (
        <EmptyState
          icon={<ShieldCheck className="h-6 w-6" />}
          title="No approvals on this version"
          description={canStart ? 'Start one above.' : undefined}
          className="mx-0"
        />
      ) : (
        <ul className="space-y-1.5">
          {rows.map((r) => (
            <li key={r.out_id}>
              <Link
                to={`/workspace/${workspaceId}/project/${projectId}/approval/${r.out_id}`}
                className="block rounded-[--radius-sm] border border-transparent p-2 hover:border-[--color-border] hover:bg-[--color-surface-2]"
              >
                <div className="flex items-center gap-2">
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">
                    {r.out_title ?? 'Untitled approval'}
                  </span>
                  <StateBadge state={r.out_status as WorkflowState} />
                </div>
                {r.out_expires_at && (
                  <p className="mt-0.5 text-[10px] text-[--color-text-subtle]">
                    expires {relative(r.out_expires_at)}
                  </p>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}

      {versionId && (
        <CreateApprovalDialog
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
