import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { ApprovalsDashboardBody } from './ApprovalsDashboardBody'

export const WorkspaceApprovalsHandle = { crumb: 'Approvals' }

export function WorkspaceApprovalsScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  if (!ws_id) return <LoadingPage />
  return (
    <ApprovalsDashboardBody
      workspaceId={ws_id}
      projectId={null}
      heading="Approvals"
      subheading={
        <p className="text-sm text-[--color-text-muted]">
          All approval requests across every project in this workspace.
        </p>
      }
    />
  )
}
