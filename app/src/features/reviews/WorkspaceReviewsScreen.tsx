import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { ReviewsDashboardBody } from './ReviewsDashboardBody'

export const WorkspaceReviewsHandle = { crumb: 'Reviews' }

export function WorkspaceReviewsScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  if (!ws_id) return <LoadingPage />
  return (
    <ReviewsDashboardBody
      workspaceId={ws_id}
      projectId={null}
      heading="Reviews"
      subheading={
        <p className="text-sm text-[--color-text-muted]">
          All reviews across every project in this workspace.
        </p>
      }
    />
  )
}
