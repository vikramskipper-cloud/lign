import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { ReleasesDashboardBody } from './ReleasesDashboardBody'

export const WorkspaceReleasesHandle = { crumb: 'Releases' }

export function WorkspaceReleasesScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  if (!ws_id) return <LoadingPage />
  return (
    <ReleasesDashboardBody
      workspaceId={ws_id}
      projectId={null}
      heading="Releases"
      subheading={
        <p className="text-sm text-[--color-text-muted]">
          All releases across every project in this workspace.
        </p>
      }
    />
  )
}
