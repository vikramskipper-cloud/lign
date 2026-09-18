import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { ReviewsDashboardBody } from './ReviewsDashboardBody'
import { useProjectReviewMetrics } from './queries'

export const ProjectReviewsHandle = { crumb: 'Reviews' }

export function ProjectReviewsScreen() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()
  const metrics = useProjectReviewMetrics(proj_id)

  if (!ws_id || !proj_id) return <LoadingPage />

  return (
    <ReviewsDashboardBody
      workspaceId={ws_id}
      projectId={proj_id}
      heading="Reviews"
      metricsSlot={
        metrics.data ? (
          <div className="flex gap-4 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-4 py-3 text-sm">
            <MetricBlock label="Outstanding" value={metrics.data.outstanding_count} />
            <MetricBlock label="Overdue" value={metrics.data.overdue_count} accent />
          </div>
        ) : null
      }
    />
  )
}

function MetricBlock({ label, value, accent }: { label: string; value: number; accent?: boolean }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">{label}</div>
      <div
        className={
          'text-lg font-semibold ' + (accent && value > 0 ? 'text-[--color-danger]' : 'text-[--color-text]')
        }
      >
        {value}
      </div>
    </div>
  )
}
