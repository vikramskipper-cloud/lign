import {lazy,Suspense} from 'react'
import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { ReviewsDashboardBody } from './ReviewsDashboardBody'

const InternalReviewQueue=lazy(()=>import('@/features/version-access/InternalReviewQueue'))
export const WorkspaceReviewsHandle = { crumb: 'Reviews' }

export function WorkspaceReviewsScreen() {
  const { ws_id } = useParams<{ ws_id: string }>()
  if (!ws_id) return <LoadingPage />
  return (
    <><Suspense fallback={null}><InternalReviewQueue workspaceId={ws_id}/></Suspense><ReviewsDashboardBody
      workspaceId={ws_id}
      projectId={null}
      heading="Reviews"
      subheading={
        <p className="text-sm text-[--color-text-muted]">
          All reviews across every project in this workspace.
        </p>
      }
    /></>
  )
}
