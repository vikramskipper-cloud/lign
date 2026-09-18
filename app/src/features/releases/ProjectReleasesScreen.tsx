import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { ReleasesDashboardBody } from './ReleasesDashboardBody'
import { useProjectReleaseMetrics } from './queries'

export const ProjectReleasesHandle = { crumb: 'Releases' }

export function ProjectReleasesScreen() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()
  const metrics = useProjectReleaseMetrics(proj_id)
  if (!ws_id || !proj_id) return <LoadingPage />

  return (
    <ReleasesDashboardBody
      workspaceId={ws_id}
      projectId={proj_id}
      heading="Releases"
      metricsSlot={
        metrics.data ? (
          <div className="flex flex-wrap gap-4 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-4 py-3 text-sm">
            <MetricBlock label="Drafts" value={metrics.data.total_draft} />
            <MetricBlock label="Released" value={metrics.data.total_released} />
            <MetricBlock label="Withdrawn" value={metrics.data.total_withdrawn} />
            <MetricBlock
              label="Trailing 30d"
              value={metrics.data.released_trailing_30d}
            />
            <MetricBlock
              label="Trailing 90d"
              value={metrics.data.released_trailing_90d}
            />
            <MetricBlock
              label="Chain heads"
              value={metrics.data.chain_head_count}
            />
          </div>
        ) : null
      }
    />
  )
}

function MetricBlock({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        {label}
      </div>
      <div className="text-lg font-semibold text-[--color-text]">{value}</div>
    </div>
  )
}
