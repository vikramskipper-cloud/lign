import { useParams } from 'react-router'
import { LoadingPage } from '@/ui/loading-page'
import { RequirementsDashboardBody } from './RequirementsDashboardBody'
import { useProjectRequirementMetrics } from './queries'

export const ProjectRequirementsHandle = { crumb: 'Requirements' }

export function ProjectRequirementsScreen() {
  const { ws_id, proj_id } = useParams<{ ws_id: string; proj_id: string }>()
  const metrics = useProjectRequirementMetrics(proj_id)

  if (!ws_id || !proj_id) return <LoadingPage />

  return (
    <RequirementsDashboardBody
      workspaceId={ws_id}
      projectId={proj_id}
      heading="Requirements"
      metricsSlot={
        metrics.data ? (
          <div className="flex flex-wrap gap-4 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] px-4 py-3 text-sm">
            <MetricBlock label="Total" value={metrics.data.total_count} />
            <MetricBlock
              label="Critical unsat."
              value={metrics.data.critical_unsatisfied_count}
              accent
            />
            <MetricBlock
              label="Overdue"
              value={metrics.data.overdue_count}
              accent
            />
            <MetricBlock
              label="Unassessed (latest)"
              value={metrics.data.unassessed_on_latest_count}
            />
            <MetricBlock
              label="Coverage"
              value={metrics.data.coverage_rate}
              suffix="%"
            />
          </div>
        ) : null
      }
    />
  )
}

function MetricBlock({
  label,
  value,
  accent,
  suffix,
}: {
  label: string
  value: number
  accent?: boolean
  suffix?: string
}) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        {label}
      </div>
      <div
        className={
          'text-lg font-semibold ' +
          (accent && value > 0 ? 'text-[--color-danger]' : 'text-[--color-text]')
        }
      >
        {value}
        {suffix}
      </div>
    </div>
  )
}
