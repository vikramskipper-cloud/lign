import * as React from 'react'
import { Link } from 'react-router'
import { ListChecks } from 'lucide-react'
import { EmptyState } from '@/ui/empty-state'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { Button } from '@/ui/button'
import { useApplicableRequirementsForAsset } from './queries'
import { RequirementAssessmentDialog } from './RequirementAssessmentDialog'

interface Props {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string | null
  canAssess: boolean
}

/**
 * APP 008 §19.4: Design Workspace RightPanel Requirements tab. Reads
 * frozen list_applicable_requirements and offers an inline assess action.
 */
export function RequirementsTabPanel({
  workspaceId,
  projectId,
  assetId,
  versionId,
  canAssess,
}: Props) {
  const q = useApplicableRequirementsForAsset(assetId, versionId)
  const [dialogFor, setDialogFor] = React.useState<{
    requirementId: string
    code: string
    previousStatus?: 'satisfied' | 'partial' | 'not_satisfied' | 'not_applicable' | null
  } | null>(null)

  if (!versionId) {
    return (
      <div className="p-3 text-sm text-[--color-text-muted]">
        Select a version to view applicable requirements.
      </div>
    )
  }

  if (q.isLoading) {
    return <p className="p-3 text-xs text-[--color-text-muted]">Loading…</p>
  }
  const rows = q.data ?? []

  if (rows.length === 0) {
    return (
      <div className="p-3">
        <EmptyState
          icon={<ListChecks className="h-6 w-6" />}
          title="No requirements apply to this asset"
          description="Create one from the project Requirements screen."
          className="mx-0"
        />
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-2 p-3">
      <ul className="space-y-1.5">
        {rows.map((r) => (
          <li
            key={r.out_requirement_id}
            className="flex items-start gap-2 rounded-[--radius-sm] border border-transparent p-2 hover:border-[--color-border] hover:bg-[--color-surface-2]"
          >
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] text-[--color-text-muted]">
                  {r.out_code}
                </span>
                <Link
                  to={`/workspace/${workspaceId}/project/${projectId}/requirement/${r.out_requirement_id}?requirement=${r.out_requirement_id}`}
                  className="min-w-0 flex-1 truncate text-sm font-medium hover:underline"
                >
                  {r.out_title}
                </Link>
              </div>
              <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[10px] text-[--color-text-subtle]">
                {r.out_is_project_wide && <span>project-wide</span>}
                {r.out_assessment_status && (
                  <StateBadge
                    state={r.out_assessment_status as WorkflowState}
                    label={r.out_assessment_status}
                  />
                )}
                {!r.out_assessment_status && (
                  <span className="text-[--color-warning]">
                    Not yet assessed
                  </span>
                )}
              </div>
            </div>
            {canAssess && (
              <Button
                size="sm"
                variant="secondary"
                onClick={() =>
                  setDialogFor({
                    requirementId: r.out_requirement_id,
                    code: r.out_code,
                    previousStatus: r.out_assessment_status,
                  })
                }
              >
                Assess
              </Button>
            )}
          </li>
        ))}
      </ul>

      {dialogFor && (
        <RequirementAssessmentDialog
          workspaceId={workspaceId}
          requirementId={dialogFor.requirementId}
          requirementCode={dialogFor.code}
          assetVersionId={versionId}
          previousStatus={dialogFor.previousStatus ?? null}
          open={Boolean(dialogFor)}
          onOpenChange={(open) => !open && setDialogFor(null)}
        />
      )}
    </div>
  )
}
