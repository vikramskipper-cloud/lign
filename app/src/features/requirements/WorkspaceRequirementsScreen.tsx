import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { RequirementsDashboardBody } from './RequirementsDashboardBody'

export const WorkspaceRequirementsHandle = { crumb: 'Requirements' }

export function WorkspaceRequirementsScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  if (!ws_id) return <LoadingPage />
  return (
    <RequirementsDashboardBody
      workspaceId={ws_id}
      projectId={null}
      heading="Requirements"
      subheading={
        <p className="text-sm text-[--color-text-muted]">
          All requirements across every project in this workspace.
        </p>
      }
    />
  )
}
