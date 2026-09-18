import { Link, useParams, useSearchParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/ui/tabs'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { PriorityBadge } from './PriorityBadge'
import { ScopeChip } from './ScopeChip'
import { RequirementActions } from './RequirementActions'
import { RequirementApplicabilityEditor } from './RequirementApplicabilityEditor'
import { RequirementTraceabilityView } from './RequirementTraceabilityView'
import { RequirementDiscussionsPanel } from './RequirementDiscussionsPanel'
import { useProjectCapabilities } from '@/lib/capabilities'
import { supabase } from '@/lib/supabase'
import { relative, absolute } from '@/lib/formatDate'
import { qk } from '@/lib/queryKeys'
import {
  useRequirement,
  useRequirementChain,
  useRequirementHistory,
} from './queries'

export const RequirementDetailHandle = { crumb: 'Requirement' }

const stateFromStatus = (
  status: 'draft' | 'active' | 'superseded' | 'archived',
): WorkflowState => status as WorkflowState

type Tab =
  | 'overview'
  | 'applicability'
  | 'assessments'
  | 'history'
  | 'discussions'
  | 'traceability'

const TAB_VALUES: Tab[] = [
  'overview',
  'applicability',
  'assessments',
  'history',
  'discussions',
  'traceability',
]

export function RequirementDetailScreen() {
  const { ws_id, proj_id, requirement_id } = useParams<{
    ws_id: string
    proj_id: string
    requirement_id: string
  }>()
  const [searchParams, setSearchParams] = useSearchParams()
  const rawTab = searchParams.get('tab') as Tab | null
  const tab: Tab = TAB_VALUES.includes(rawTab as Tab)
    ? (rawTab as Tab)
    : 'overview'

  const detail = useRequirement(requirement_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const chain = useRequirementChain(requirement_id)
  const history = useRequirementHistory(requirement_id)

  const bookmarksQ = useQuery({
    queryKey: ws_id ? qk.bookmarks(ws_id, 'requirement') : ['bookmarks', 'none'],
    enabled: Boolean(ws_id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('user_bookmarks')
        .select('subject_id')
        .eq('subject_kind', 'requirement')
      if (error) throw error
      return new Set((data ?? []).map((r) => r.subject_id as string))
    },
  })

  const setTab = (v: string) => {
    const next = new URLSearchParams(searchParams)
    if (v === 'overview') next.delete('tab')
    else next.set('tab', v)
    setSearchParams(next, { replace: true })
  }

  if (detail.isLoading) return <LoadingPage />
  if (
    detail.isError ||
    !detail.data ||
    !ws_id ||
    !proj_id ||
    !requirement_id
  ) {
    return (
      <div className="p-8">
        <EmptyState
          title="Requirement not found"
          description="It may have been deleted or you may not have access."
          action={
            <Button asChild size="sm" variant="secondary">
              <Link to={`/workspace/${ws_id}/project/${proj_id}/requirements`}>
                Back to requirements
              </Link>
            </Button>
          }
        />
      </div>
    )
  }

  const d = detail.data
  const r = d.requirement
  const app = d.applicability_summary
  const canEdit = Boolean(caps.data?.['requirement.edit'])

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <Link
            to={`/workspace/${ws_id}/project/${proj_id}/requirements`}
            className="inline-flex items-center gap-1 text-xs text-[--color-text-muted] hover:text-[--color-text]"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Back to requirements
          </Link>
          <div className="flex items-center gap-2">
            <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] uppercase text-[--color-text-muted]">
              {r.code}
            </span>
            <h1 className="truncate text-xl font-semibold">{r.title}</h1>
            <StateBadge state={stateFromStatus(r.status)} />
            <PriorityBadge priority={r.priority} />
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {r.category_kind && <ScopeChip label={r.category_kind} />}
            {r.source_kind && <ScopeChip label={r.source_kind} />}
            <ScopeChip
              label={
                app.is_project_wide
                  ? 'Project-wide'
                  : `${app.asset_count} asset${
                      app.asset_count === 1 ? '' : 's'
                    }`
              }
              tone="muted"
            />
          </div>
          {r.description && (
            <p className="max-w-3xl whitespace-pre-wrap text-sm text-[--color-text-muted]">
              {r.description}
            </p>
          )}
        </div>
        <RequirementActions
          workspaceId={ws_id}
          projectId={proj_id}
          requirementId={requirement_id}
          code={r.code}
          status={r.status}
          caps={caps.data}
          isBookmarked={Boolean(bookmarksQ.data?.has(requirement_id))}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <aside className="space-y-3">
          <MetadataCard
            requirement={r}
            metrics={d.metrics}
            appSummary={app}
          />
          {chain.data && chain.data.length > 1 && (
            <ChainCard
              workspaceId={ws_id}
              projectId={proj_id}
              currentId={requirement_id}
              chain={chain.data}
            />
          )}
          {d.sub_requirements.length > 0 && (
            <SubReqsCard
              workspaceId={ws_id}
              projectId={proj_id}
              subs={d.sub_requirements}
            />
          )}
        </aside>

        <div className="lg:col-span-2 space-y-3">
          <Tabs
            value={tab}
            onValueChange={setTab}
            className="rounded-[--radius-md] border border-[--color-border] bg-[--color-surface]"
          >
            <TabsList>
              <TabsTrigger value="overview">Overview</TabsTrigger>
              <TabsTrigger value="applicability">Applicability</TabsTrigger>
              <TabsTrigger value="assessments">
                Assessments
                <span className="ml-1 rounded-full bg-[--color-surface-2] px-1.5 text-[10px] text-[--color-text-muted]">
                  {d.assessment_summary.versions_assessed}/
                  {d.assessment_summary.versions_applicable}
                </span>
              </TabsTrigger>
              <TabsTrigger value="history">History</TabsTrigger>
              <TabsTrigger value="discussions">Discussions</TabsTrigger>
              <TabsTrigger value="traceability">Traceability</TabsTrigger>
            </TabsList>
            <TabsContent value="overview" className="m-0 space-y-3 p-3">
              <OverviewTab detail={d} />
            </TabsContent>
            <TabsContent value="applicability" className="m-0 p-3">
              <RequirementApplicabilityEditor
                workspaceId={ws_id}
                projectId={proj_id}
                requirementId={requirement_id}
                parentRequirementId={r.parent_requirement_id}
                currentAssetIds={app.asset_ids}
                canEdit={canEdit}
              />
            </TabsContent>
            <TabsContent value="assessments" className="m-0 p-3">
              <AssessmentsTab detail={d} />
            </TabsContent>
            <TabsContent value="history" className="m-0 p-3">
              {history.isLoading ? (
                <p className="text-xs text-[--color-text-muted]">Loading…</p>
              ) : (history.data ?? []).length === 0 ? (
                <p className="text-xs text-[--color-text-muted]">
                  No activity yet.
                </p>
              ) : (
                <ul className="space-y-1">
                  {(history.data ?? []).map((e) => (
                    <li
                      key={e.id}
                      className="rounded-[--radius-sm] px-2 py-1.5 text-xs hover:bg-[--color-surface-2]"
                    >
                      <div className="font-medium">{e.event_type}</div>
                      <div
                        className="text-[10px] text-[--color-text-subtle]"
                        title={absolute(e.occurred_at)}
                      >
                        {relative(e.occurred_at)}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </TabsContent>
            <TabsContent value="discussions" className="m-0">
              <RequirementDiscussionsPanel
                workspaceId={ws_id}
                requirementId={requirement_id}
                canComment={Boolean(caps.data?.['comment.create'])}
              />
            </TabsContent>
            <TabsContent value="traceability" className="m-0">
              <RequirementTraceabilityView
                workspaceId={ws_id}
                projectId={proj_id}
                requirementId={requirement_id}
              />
            </TabsContent>
          </Tabs>
        </div>
      </div>
    </div>
  )
}

function MetadataCard({
  requirement,
  metrics,
  appSummary,
}: {
  requirement: import('./queries').RequirementRow
  metrics: import('./queries').RequirementDetail['metrics']
  appSummary: import('./queries').RequirementDetail['applicability_summary']
}) {
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        Metadata
      </div>
      <div className="space-y-1 text-xs">
        <div>
          <span className="text-[--color-text-subtle]">Owner: </span>
          <span className="font-mono">
            {requirement.owner_profile_id?.slice(0, 8) ?? 'unassigned'}
          </span>
        </div>
        <div>
          <span className="text-[--color-text-subtle]">Created: </span>
          <span title={absolute(requirement.created_at)}>
            {relative(requirement.created_at)}
          </span>
        </div>
        <div>
          <span className="text-[--color-text-subtle]">Updated: </span>
          <span title={absolute(requirement.updated_at)}>
            {relative(requirement.updated_at)}
          </span>
        </div>
        {requirement.source_ref && (
          <div>
            <span className="text-[--color-text-subtle]">Source ref: </span>
            <span className="font-mono">{requirement.source_ref}</span>
          </div>
        )}
        {requirement.due_at && (
          <div>
            <span className="text-[--color-text-subtle]">Due: </span>
            <span title={absolute(requirement.due_at)}>
              {relative(requirement.due_at)}
            </span>
          </div>
        )}
        {requirement.verification_method && (
          <div>
            <span className="text-[--color-text-subtle]">Verification: </span>
            <span>{requirement.verification_method}</span>
          </div>
        )}
        <div className="pt-2 text-[10px] text-[--color-text-subtle]">
          Coverage {metrics.coverage_pct}% · {appSummary.asset_count}{' '}
          applicable asset{appSummary.asset_count === 1 ? '' : 's'}
        </div>
      </div>
    </div>
  )
}

function ChainCard({
  workspaceId,
  projectId,
  currentId,
  chain,
}: {
  workspaceId: string
  projectId: string
  currentId: string
  chain: import('./queries').RequirementChainRow[]
}) {
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        Supersession chain
      </div>
      <ul className="space-y-1">
        {chain.map((c) => (
          <li key={c.requirement_id}>
            <Link
              to={`/workspace/${workspaceId}/project/${projectId}/requirement/${c.requirement_id}`}
              className={
                'flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-xs ' +
                (c.requirement_id === currentId
                  ? 'bg-[--color-surface-2] font-medium'
                  : 'hover:bg-[--color-surface-2]')
              }
            >
              <span className="font-mono text-[10px] text-[--color-text-muted]">
                {c.code}
              </span>
              <span className="flex-1 truncate">{c.title}</span>
              <StateBadge state={c.status as WorkflowState} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}

function SubReqsCard({
  workspaceId,
  projectId,
  subs,
}: {
  workspaceId: string
  projectId: string
  subs: import('./queries').RequirementRow[]
}) {
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        Sub-requirements
      </div>
      <ul className="space-y-1">
        {subs.map((s) => (
          <li key={s.id}>
            <Link
              to={`/workspace/${workspaceId}/project/${projectId}/requirement/${s.id}`}
              className="flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-xs hover:bg-[--color-surface-2]"
            >
              <span className="font-mono text-[10px] text-[--color-text-muted]">
                {s.code}
              </span>
              <span className="flex-1 truncate">{s.title}</span>
              <PriorityBadge priority={s.priority} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}

function OverviewTab({
  detail,
}: {
  detail: import('./queries').RequirementDetail
}) {
  const r = detail.requirement
  return (
    <div className="space-y-3">
      {!r.description && (
        <div className="rounded-[--radius-sm] border border-dashed border-[--color-border] p-3 text-xs text-[--color-text-subtle]">
          Add a description on the Applicability tab or via edit.
        </div>
      )}
      <div className="rounded-[--radius-sm] border border-[--color-border] p-3 text-xs">
        <div className="font-medium">Applies to</div>
        <p className="mt-1 text-[--color-text-muted]">
          {detail.applicability_summary.is_project_wide
            ? 'Every design asset in this project.'
            : `${detail.applicability_summary.asset_count} scoped asset${
                detail.applicability_summary.asset_count === 1 ? '' : 's'
              }.`}
        </p>
      </div>
      <div className="grid grid-cols-3 gap-2 text-xs">
        <MetricPill
          label="Coverage"
          value={`${detail.metrics.coverage_pct}%`}
        />
        <MetricPill
          label="Days since assessed"
          value={
            detail.metrics.days_since_last_assessment == null
              ? '—'
              : String(detail.metrics.days_since_last_assessment)
          }
        />
        <MetricPill
          label="Days until due"
          value={
            detail.metrics.days_until_due == null
              ? '—'
              : String(detail.metrics.days_until_due)
          }
        />
      </div>
    </div>
  )
}

function AssessmentsTab({
  detail,
}: {
  detail: import('./queries').RequirementDetail
}) {
  const entries = Object.entries(detail.assessment_summary.latest_status_per_asset)
  if (entries.length === 0) {
    return (
      <p className="text-xs text-[--color-text-muted]">
        No assessments recorded yet. Assess from the Design Workspace
        Requirements tab on the applicable version.
      </p>
    )
  }
  return (
    <ul className="space-y-1">
      {entries.map(([assetId, status]) => (
        <li
          key={assetId}
          className="flex items-center gap-2 rounded-[--radius-sm] border border-[--color-border] px-2 py-1.5 text-xs"
        >
          <span className="font-mono text-[10px] text-[--color-text-subtle]">
            {assetId.slice(0, 8)}
          </span>
          <span className="ml-auto">
            {status === 'unassessed' ? (
              <span className="text-[--color-warning]">unassessed</span>
            ) : (
              <span>{status}</span>
            )}
          </span>
        </li>
      ))}
    </ul>
  )
}

function MetricPill({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[--radius-sm] border border-[--color-border] p-2 text-center">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        {label}
      </div>
      <div className="text-base font-semibold">{value}</div>
    </div>
  )
}
