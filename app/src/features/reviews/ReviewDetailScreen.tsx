import * as React from 'react'
import { Link, useParams, useSearchParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, ExternalLink } from 'lucide-react'
import { Button } from '@/ui/button'
import { EmptyState } from '@/ui/empty-state'
import { LoadingPage } from '@/ui/loading-page'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/ui/tabs'
import { StateBadge, type WorkflowState } from '@/features/shared/StateBadge'
import { useProjectCapabilities } from '@/lib/capabilities'
import { useSession } from '@/auth/SessionProvider'
import { supabase } from '@/lib/supabase'
import { relative, absolute } from '@/lib/formatDate'
import { qk } from '@/lib/queryKeys'
import { useReviewDetail, useReviewChain, type ReviewStatus } from './queries'
import { ReviewActions } from './ReviewActions'
import { RosterEditor } from './RosterEditor'
import { CommentsPanel } from '@/features/comments/CommentsPanel'
import { FilesPanel } from '@/features/files/FilesPanel'
import { useVersionFiles } from '@/features/files/queries'
import { useWorkspaceHotkeys } from '@/features/design-workspace/useWorkspaceHotkeys'

export const ReviewDetailHandle = { crumb: 'Review' }

const stateFromReview = (status: ReviewStatus): WorkflowState => status as WorkflowState

export function ReviewDetailScreen() {
  const { ws_id, proj_id, review_id } = useParams<{
    ws_id: string
    proj_id: string
    review_id: string
  }>()
  const [searchParams, setSearchParams] = useSearchParams()
  const tab =
    (searchParams.get('tab') as 'comments' | 'participants' | 'activity' | 'files' | null) ??
    'comments'
  const focusedParticipant = searchParams.get('participant')
  const rosterRef = React.useRef<HTMLDivElement | null>(null)
  const { user } = useSession()

  const detail = useReviewDetail(review_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const chain = useReviewChain(detail.data?.review.root_review_id)

  const isBookmarkedQ = useQuery({
    queryKey: ws_id ? qk.bookmarks(ws_id, 'review') : ['bookmarks', 'none'],
    enabled: Boolean(ws_id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('user_bookmarks')
        .select('subject_id')
        .eq('subject_kind', 'review')
      if (error) throw error
      return new Set((data ?? []).map((r) => r.subject_id as string))
    },
  })

  useWorkspaceHotkeys({
    onFocusRoster: () => {
      setTab('participants')
      rosterRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    },
    onEscape: () => {
      if (searchParams.get('participant')) {
        const next = new URLSearchParams(searchParams)
        next.delete('participant')
        setSearchParams(next, { replace: true })
      }
    },
  })

  const setTab = (v: string) => {
    const next = new URLSearchParams(searchParams)
    if (v === 'comments') next.delete('tab')
    else next.set('tab', v)
    setSearchParams(next, { replace: true })
  }

  if (detail.isLoading) return <LoadingPage />
  if (detail.isError || !detail.data || !ws_id || !proj_id || !review_id) {
    return (
      <div className="p-8">
        <EmptyState
          title="Review not found"
          description="It may have been deleted or you may not have access."
          action={
            <Button asChild size="sm" variant="secondary">
              <Link to={`/workspace/${ws_id}/project/${proj_id}/reviews`}>Back to reviews</Link>
            </Button>
          }
        />
      </div>
    )
  }

  const r = detail.data.review
  const participants = detail.data.participants
  const metrics = detail.data.metrics

  const myPending = participants.some(
    (p) => !p.removed_at && p.status === 'pending' && p.profile_id === user?.id,
  )

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <Link
            to={`/workspace/${ws_id}/project/${proj_id}/reviews`}
            className="inline-flex items-center gap-1 text-xs text-[--color-text-muted] hover:text-[--color-text]"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Back to reviews
          </Link>
          <div className="flex items-center gap-2">
            <h1 className="truncate text-xl font-semibold">{r.title}</h1>
            <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] text-[--color-text-muted]">
              R{r.round_number}
            </span>
            <StateBadge state={stateFromReview(r.status)} />
          </div>
          {r.description && (
            <p className="text-sm text-[--color-text-muted]">{r.description}</p>
          )}
          {r.cancellation_reason && (
            <p className="text-xs text-[--color-danger]">Cancelled: {r.cancellation_reason}</p>
          )}
        </div>
        <ReviewActions
          detail={detail.data}
          caps={caps.data}
          isBookmarked={Boolean(isBookmarkedQ.data?.has(r.id))}
          isMyPending={myPending}
        />
      </div>

      {metrics.newer_version_exists && (
        <div className="rounded-[--radius-md] border border-[--color-warning]/40 bg-[--color-warning]/10 px-3 py-2 text-xs text-[--color-text-muted]">
          A newer version of this asset is available.{' '}
          <Link
            to={`/workspace/${ws_id}/project/${proj_id}/asset/${r.design_asset_id}`}
            className="underline"
          >
            View current version
          </Link>
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        {/* Version card + Timeline (col span 1) */}
        <aside className="space-y-3">
          <VersionCard workspaceId={ws_id} projectId={proj_id} detail={detail.data} />
          <TimelineCard
            workspaceId={ws_id}
            projectId={proj_id}
            currentReviewId={r.id}
            chain={chain.data ?? []}
          />
        </aside>

        {/* Main content — tabs (col span 2) */}
        <div className="lg:col-span-2 space-y-3">
          <RosterEditor
            workspaceId={ws_id}
            projectId={proj_id}
            reviewId={r.id}
            reviewStatus={r.status}
            participants={participants}
            canCoordinate={Boolean(caps.data?.['review.coordinate'])}
            focusedParticipantId={focusedParticipant}
            focusRef={rosterRef}
          />

          <Tabs value={tab} onValueChange={setTab} className="rounded-[--radius-md] border border-[--color-border] bg-[--color-surface]">
            <TabsList>
              <TabsTrigger value="comments">Comments</TabsTrigger>
              <TabsTrigger value="participants">
                Participants
                <span className="ml-1 rounded-full bg-[--color-surface-2] px-1.5 text-[10px] text-[--color-text-muted]">
                  {participants.filter((p) => !p.removed_at).length}
                </span>
              </TabsTrigger>
              <TabsTrigger value="activity">Activity</TabsTrigger>
              <TabsTrigger value="files">Files</TabsTrigger>
            </TabsList>
            <TabsContent value="comments" className="m-0">
              <CommentsPanel
                workspaceId={ws_id}
                projectId={proj_id}
                versionId={r.version_id}
                canComment={Boolean(caps.data?.['comment.create'])}
                canResolve={Boolean(caps.data?.['comment.resolve'])}
                canEditOwn={Boolean(caps.data?.['comment.edit_own'])}
              />
            </TabsContent>
            <TabsContent value="participants" className="m-0 p-3">
              <p className="text-xs text-[--color-text-muted]">
                Roster management is above. Distribution:
              </p>
              <div className="mt-2 grid grid-cols-4 gap-2 text-xs">
                <MetricPill label="Signed off" value={metrics.response_distribution.signed_off} />
                <MetricPill label="Commented" value={metrics.response_distribution.commented} />
                <MetricPill label="Declined" value={metrics.response_distribution.declined} />
                <MetricPill label="Pending" value={metrics.response_distribution.pending} />
              </div>
            </TabsContent>
            <TabsContent value="activity" className="m-0 p-3">
              <ActivityTab reviewId={r.id} />
            </TabsContent>
            <TabsContent value="files" className="m-0">
              <FilesTab workspaceId={ws_id} projectId={proj_id} assetId={r.design_asset_id} versionId={r.version_id} />
            </TabsContent>
          </Tabs>
        </div>
      </div>
    </div>
  )
}

function MetricPill({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-[--radius-sm] border border-[--color-border] p-2 text-center">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">{label}</div>
      <div className="text-lg font-semibold">{value}</div>
    </div>
  )
}

function VersionCard({
  workspaceId,
  projectId,
  detail,
}: {
  workspaceId: string
  projectId: string
  detail: import('./queries').ReviewDetail
}) {
  const r = detail.review
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">Version</div>
      <div>
        <p className="text-xs text-[--color-text-muted]">Anchored to a specific published version.</p>
      </div>
      <Button asChild size="sm" variant="secondary" className="w-full">
        <Link to={`/workspace/${workspaceId}/project/${projectId}/asset/${r.design_asset_id}/v/${r.version_id}?review=${r.id}`}>
          <ExternalLink className="mr-1 h-3.5 w-3.5" />
          Open in workspace
        </Link>
      </Button>
      {detail.metrics.opened_at && (
        <div className="text-[10px] text-[--color-text-subtle]" title={absolute(detail.metrics.opened_at)}>
          Opened {relative(detail.metrics.opened_at)}
        </div>
      )}
      {detail.metrics.first_responded_at && (
        <div className="text-[10px] text-[--color-text-subtle]" title={absolute(detail.metrics.first_responded_at)}>
          First response {relative(detail.metrics.first_responded_at)}
        </div>
      )}
    </div>
  )
}

function TimelineCard({
  workspaceId,
  projectId,
  currentReviewId,
  chain,
}: {
  workspaceId: string
  projectId: string
  currentReviewId: string
  chain: import('./queries').ReviewChainRow[]
}) {
  if (chain.length === 0) return null
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">Rounds</div>
      <ul className="space-y-1">
        {chain.map((c) => (
          <li key={c.out_id}>
            <Link
              to={`/workspace/${workspaceId}/project/${projectId}/review/${c.out_id}`}
              className={
                'flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-xs ' +
                (c.out_id === currentReviewId
                  ? 'bg-[--color-surface-2] font-medium'
                  : 'hover:bg-[--color-surface-2]')
              }
            >
              <span className="font-mono">R{c.out_round_number}</span>
              <span className="flex-1 truncate">{c.out_title}</span>
              <StateBadge state={c.out_status as WorkflowState} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}

function ActivityTab({ reviewId }: { reviewId: string }) {
  const q = useQuery({
    queryKey: ['review', reviewId, 'activity'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('activity_events')
        .select('id, event_type, occurred_at, actor_profile_id, payload, subject_label')
        .or(`subject_id.eq.${reviewId}`)
        .order('occurred_at', { ascending: false })
        .limit(100)
      if (error) throw error
      return data ?? []
    },
  })
  if (q.isLoading) return <p className="text-xs text-[--color-text-muted]">Loading…</p>
  if (q.isError) return <p className="text-xs text-[--color-danger]">Couldn't load activity.</p>
  const rows = q.data ?? []
  if (rows.length === 0) return <p className="text-xs text-[--color-text-muted]">No activity yet.</p>
  return (
    <ul className="space-y-1">
      {rows.map((e) => (
        <li key={e.id} className="rounded-[--radius-sm] px-2 py-1.5 text-xs hover:bg-[--color-surface-2]">
          <div className="font-medium">{e.event_type}</div>
          <div className="text-[10px] text-[--color-text-subtle]" title={absolute(e.occurred_at as string)}>
            {relative(e.occurred_at as string)}
          </div>
        </li>
      ))}
    </ul>
  )
}

function FilesTab({
  workspaceId,
  projectId,
  assetId,
  versionId,
}: {
  workspaceId: string
  projectId: string
  assetId: string
  versionId: string
}) {
  const files = useVersionFiles(versionId)
  return (
    <FilesPanel
      workspaceId={workspaceId}
      projectId={projectId}
      assetId={assetId}
      versionId={versionId}
      files={files.data ?? []}
      activeFileId={null}
      isDraft={false}
    />
  )
}
