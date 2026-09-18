import { Link, useParams, useSearchParams } from 'react-router'
import { ChevronLeft, Package } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/ui/tabs'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { relative, absolute } from '@/lib/formatDate'
import { useProjectCapabilities } from '@/lib/capabilities'
import {
  useRelease,
  useReleaseChain,
  useReleaseItems,
  type ReleaseChainNode,
  type ReleaseDetail,
} from './queries'
import { ReleaseActions } from './ReleaseActions'
import { ReleaseEvidenceCard } from './ReleaseEvidenceCard'
import { ReleaseComparisonView } from './ReleaseComparisonView'
import { ReleaseHistoryList } from './ReleaseHistoryList'
import { ReleaseNotesEditor } from './ReleaseNotesEditor'

export const ReleaseDetailHandle = { crumb: 'Release' }

type Tab = 'overview' | 'evidence' | 'comparison' | 'history' | 'notes'
const TAB_VALUES: Tab[] = ['overview', 'evidence', 'comparison', 'history', 'notes']

const stateFromStatus = (s: ReleaseDetail['status']): WorkflowState =>
  s as WorkflowState

export function ReleaseDetailScreen() {
  const { ws_id, proj_id, release_id } = useParams<{
    ws_id: string
    proj_id: string
    release_id: string
  }>()
  const [searchParams, setSearchParams] = useSearchParams()
  const rawTab = searchParams.get('tab') as Tab | null
  const tab: Tab = TAB_VALUES.includes(rawTab as Tab)
    ? (rawTab as Tab)
    : 'overview'

  const detail = useRelease(release_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const chain = useReleaseChain(release_id)
  const items = useReleaseItems(release_id)

  const setTab = (v: string) => {
    const next = new URLSearchParams(searchParams)
    if (v === 'overview') next.delete('tab')
    else next.set('tab', v)
    setSearchParams(next, { replace: true })
  }

  if (detail.isLoading) return <LoadingPage />
  if (detail.isError || !detail.data || !ws_id || !proj_id || !release_id) {
    return (
      <div className="p-8">
        <EmptyState
          title="Release not found"
          description="It may have been discarded or you may not have access."
          action={
            <Button asChild size="sm" variant="secondary">
              <Link to={`/workspace/${ws_id}/project/${proj_id}/releases`}>
                Back to releases
              </Link>
            </Button>
          }
        />
      </div>
    )
  }

  const r = detail.data
  const canEdit = Boolean(caps.data?.['release.create'])

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <Link
            to={`/workspace/${ws_id}/project/${proj_id}/releases`}
            className="inline-flex items-center gap-1 text-xs text-[--color-text-muted] hover:text-[--color-text]"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Back to releases
          </Link>
          <div className="flex items-center gap-2">
            {r.code && (
              <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] uppercase text-[--color-text-muted]">
                {r.code}
              </span>
            )}
            <h1 className="truncate text-xl font-semibold">{r.name}</h1>
            <StateBadge state={stateFromStatus(r.status)} />
            {r.release_type && (
              <span className="rounded-full bg-[--color-surface-2] px-2 py-0.5 text-[10px] uppercase tracking-wide text-[--color-text-muted]">
                {r.release_type}
              </span>
            )}
          </div>
          {r.channel && (
            <p className="text-xs text-[--color-text-muted]">
              Channel: {r.channel}
            </p>
          )}
        </div>
        <ReleaseActions
          workspaceId={ws_id}
          projectId={proj_id}
          release={r}
          caps={caps.data}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <aside className="space-y-3">
          <MetadataCard r={r} />
          {chain.data && chain.data.length > 1 && (
            <ChainCard
              workspaceId={ws_id}
              projectId={proj_id}
              currentId={r.id}
              chain={chain.data}
            />
          )}
        </aside>

        <div className="space-y-3 lg:col-span-2">
          <Tabs
            value={tab}
            onValueChange={setTab}
            className="rounded-[--radius-md] border border-[--color-border] bg-[--color-surface]"
          >
            <TabsList>
              <TabsTrigger value="overview">
                Overview
                <span className="ml-1 rounded-full bg-[--color-surface-2] px-1.5 text-[10px] text-[--color-text-muted]">
                  {r.item_count}
                </span>
              </TabsTrigger>
              <TabsTrigger value="evidence">Evidence</TabsTrigger>
              <TabsTrigger value="comparison">Comparison</TabsTrigger>
              <TabsTrigger value="history">History</TabsTrigger>
              <TabsTrigger value="notes">Notes</TabsTrigger>
            </TabsList>
            <TabsContent value="overview" className="m-0 space-y-2 p-3">
              <ItemsList items={items.data ?? []} loading={items.isLoading} />
            </TabsContent>
            <TabsContent value="evidence" className="m-0 p-3">
              <ReleaseEvidenceCard releaseId={r.id} />
            </TabsContent>
            <TabsContent value="comparison" className="m-0 p-3">
              <ReleaseComparisonView releaseId={r.id} compareToId={null} />
            </TabsContent>
            <TabsContent value="history" className="m-0 p-3">
              <ReleaseHistoryList releaseId={r.id} />
            </TabsContent>
            <TabsContent value="notes" className="m-0 p-3">
              <ReleaseNotesEditor
                workspaceId={ws_id}
                projectId={proj_id}
                release={r}
                canEdit={canEdit}
              />
            </TabsContent>
          </Tabs>
        </div>
      </div>
    </div>
  )
}

function MetadataCard({ r }: { r: ReleaseDetail }) {
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        Metadata
      </div>
      <div className="space-y-1 text-xs">
        <Row label="Status" value={r.status} />
        <Row label="Type" value={r.release_type ?? '—'} />
        <Row
          label="Items"
          value={String(r.item_count)}
        />
        <Row
          label="Chain"
          value={`${r.chain_position} / ${r.chain_length}`}
        />
        <Row
          label="Created"
          value={relative(r.created_at)}
          title={absolute(r.created_at)}
        />
        {r.released_at && (
          <Row
            label="Released"
            value={relative(r.released_at)}
            title={absolute(r.released_at)}
          />
        )}
        {r.withdrawn_at && (
          <Row
            label="Withdrawn"
            value={relative(r.withdrawn_at)}
            title={absolute(r.withdrawn_at)}
          />
        )}
        {r.published_by_profile_id && (
          <Row label="Published by" value={r.published_by_profile_id.slice(0, 8)} />
        )}
        {r.created_by_profile_id && (
          <Row label="Created by" value={r.created_by_profile_id.slice(0, 8)} />
        )}
      </div>
    </div>
  )
}

function Row({
  label,
  value,
  title,
}: {
  label: string
  value: string
  title?: string
}) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="text-[--color-text-subtle]">{label}</span>
      <span className="truncate" title={title}>
        {value}
      </span>
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
  chain: ReleaseChainNode[]
}) {
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        Chain
      </div>
      <ul className="space-y-1">
        {chain.map((c) => (
          <li key={c.release_id}>
            <Link
              to={`/workspace/${workspaceId}/project/${projectId}/release/${c.release_id}`}
              className={
                'flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-xs ' +
                (c.release_id === currentId
                  ? 'bg-[--color-surface-2] font-medium'
                  : 'hover:bg-[--color-surface-2]')
              }
            >
              {c.code && (
                <span className="font-mono text-[10px] text-[--color-text-muted]">
                  {c.code}
                </span>
              )}
              <span className="flex-1 truncate">{c.name}</span>
              <StateBadge state={c.status as WorkflowState} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}

function ItemsList({
  items,
  loading,
}: {
  items: import('./queries').ReleaseItemRow[]
  loading: boolean
}) {
  if (loading) {
    return <p className="text-xs text-[--color-text-muted]">Loading items…</p>
  }
  if (items.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 py-6 text-xs text-[--color-text-muted]">
        <Package className="h-6 w-6" />
        <span>No items yet. Add versions to compose this release.</span>
      </div>
    )
  }
  return (
    <ul className="space-y-2">
      {items.map((it) => (
        <li
          key={it.out_release_item_id}
          className="rounded-[--radius-sm] border border-[--color-border] p-2 text-xs"
        >
          <div className="flex items-center gap-2">
            <span className="font-mono text-[10px] text-[--color-text-muted]">
              #{it.out_sort_order ?? '?'}
            </span>
            <span className="truncate font-medium">
              {it.out_design_asset_name ?? it.out_design_asset_id.slice(0, 8)}
            </span>
            <span className="ml-auto rounded bg-[--color-surface-2] px-1 py-0.5 font-mono text-[10px]">
              v{it.out_version_sequence ?? '?'}
            </span>
          </div>
          {it.out_notes && (
            <p className="mt-1 whitespace-pre-wrap text-[--color-text-muted]">
              {it.out_notes}
            </p>
          )}
        </li>
      ))}
    </ul>
  )
}
