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
import { useApprovalDetail, useApprovalChain, type ApprovalStatus } from './queries'
import { ApprovalActions } from './ApprovalActions'
import { ApprovalRosterEditor } from './ApprovalRosterEditor'
import { CommentsPanel } from '@/features/comments/CommentsPanel'
import { FilesPanel } from '@/features/files/FilesPanel'
import { useVersionFiles } from '@/features/files/queries'
import { useWorkspaceHotkeys } from '@/features/design-workspace/useWorkspaceHotkeys'

export const ApprovalDetailHandle = { crumb: 'Approval' }

const stateFromApproval = (status: ApprovalStatus): WorkflowState => status as WorkflowState

export function ApprovalDetailScreen() {
  const { ws_id, proj_id, approval_id } = useParams<{
    ws_id: string
    proj_id: string
    approval_id: string
  }>()
  const [searchParams, setSearchParams] = useSearchParams()
  const tab =
    (searchParams.get('tab') as 'comments' | 'decisions' | 'files' | 'activity' | null) ??
    'comments'
  const focusedParticipant = searchParams.get('participant')
  const rosterRef = React.useRef<HTMLDivElement | null>(null)
  const { user } = useSession()

  const detail = useApprovalDetail(approval_id)
  const caps = useProjectCapabilities(proj_id ?? '', ws_id ?? '')
  const chain = useApprovalChain(detail.data?.request.root_approval_request_id ?? undefined)

  const isBookmarkedQ = useQuery({
    queryKey: ws_id ? qk.bookmarks(ws_id, 'approval_request') : ['bookmarks', 'none'],
    enabled: Boolean(ws_id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('user_bookmarks')
        .select('subject_id')
        .eq('subject_kind', 'approval_request')
      if (error) throw error
      return new Set((data ?? []).map((r) => r.subject_id as string))
    },
  })

  useWorkspaceHotkeys({
    onFocusRoster: () => {
      setTab('decisions')
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
  if (detail.isError || !detail.data || !ws_id || !proj_id || !approval_id) {
    return (
      <div className="p-8">
        <EmptyState
          title="Approval not found"
          description="It may have been deleted or you may not have access."
          action={
            <Button asChild size="sm" variant="secondary">
              <Link to={`/workspace/${ws_id}/project/${proj_id}/approvals`}>Back to approvals</Link>
            </Button>
          }
        />
      </div>
    )
  }

  const r = detail.data.request
  const slots = detail.data.slots
  const responses = detail.data.responses
  const metrics = detail.data.metrics

  const mySlot =
    slots.find(
      (s) => !s.removed_at && s.profile_id === user?.id,
    ) ?? null

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 space-y-1">
          <Link
            to={`/workspace/${ws_id}/project/${proj_id}/approvals`}
            className="inline-flex items-center gap-1 text-xs text-[--color-text-muted] hover:text-[--color-text]"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
            Back to approvals
          </Link>
          <div className="flex items-center gap-2">
            <h1 className="truncate text-xl font-semibold">{r.title ?? 'Untitled approval'}</h1>
            <StateBadge state={stateFromApproval(r.status)} />
            <span className="rounded bg-[--color-surface-2] px-1.5 py-0.5 font-mono text-[10px] uppercase text-[--color-text-muted]">
              {r.policy}
            </span>
          </div>
          {r.description && (
            <p className="text-sm text-[--color-text-muted]">{r.description}</p>
          )}
          {r.cancellation_reason && (
            <p className="text-xs text-[--color-danger]">Cancelled: {r.cancellation_reason}</p>
          )}
          {r.related_review_id && (
            <p className="text-xs text-[--color-text-muted]">
              Related review:{' '}
              <Link
                className="underline"
                to={`/deep/review/${r.related_review_id}`}
              >
                {r.related_review_id.slice(0, 8)}…
              </Link>
            </p>
          )}
        </div>
        <ApprovalActions
          detail={detail.data}
          caps={caps.data}
          isBookmarked={Boolean(isBookmarkedQ.data?.has(r.id))}
          mySlot={mySlot}
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <aside className="space-y-3">
          <VersionCard workspaceId={ws_id} projectId={proj_id} versionId={r.version_id} assetId={r.design_asset_id} approvalId={r.id} />
          <ChainCard
            workspaceId={ws_id}
            projectId={proj_id}
            currentId={r.id}
            chain={chain.data ?? []}
          />
        </aside>

        <div className="lg:col-span-2 space-y-3">
          <ApprovalRosterEditor
            workspaceId={ws_id}
            projectId={proj_id}
            approvalRequestId={r.id}
            approvalStatus={r.status}
            slots={slots}
            canManage={Boolean(caps.data?.['approval.request'])}
            canAssignVeto={Boolean(caps.data?.['approval.veto'])}
            focusedSlotId={focusedParticipant}
            focusRef={rosterRef}
          />

          <Tabs
            value={tab}
            onValueChange={setTab}
            className="rounded-[--radius-md] border border-[--color-border] bg-[--color-surface]"
          >
            <TabsList>
              <TabsTrigger value="comments">Comments</TabsTrigger>
              <TabsTrigger value="decisions">
                Decisions
                <span className="ml-1 rounded-full bg-[--color-surface-2] px-1.5 text-[10px] text-[--color-text-muted]">
                  {responses.length}
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
            <TabsContent value="decisions" className="m-0 p-3">
              <div className="mb-3 grid grid-cols-4 gap-2 text-xs">
                <MetricPill label="Approved" value={metrics.response_distribution.approved} />
                <MetricPill label="Rejected" value={metrics.response_distribution.rejected} />
                <MetricPill label="Abstained" value={metrics.response_distribution.abstained} />
                <MetricPill label="Pending" value={metrics.response_distribution.pending} />
              </div>
              <ul className="space-y-1">
                {responses.length === 0 && (
                  <li className="rounded-[--radius-sm] border border-dashed border-[--color-border] px-3 py-2 text-xs text-[--color-text-subtle]">
                    No decisions cast yet.
                  </li>
                )}
                {responses.map((rr) => (
                  <li
                    key={rr.id}
                    className="rounded-[--radius-sm] border border-[--color-border] px-3 py-2 text-xs"
                  >
                    <div className="font-medium">
                      {rr.decision}
                      {rr.is_veto_cast && (
                        <span className="ml-1 rounded bg-[--color-warning]/15 px-1 py-0 text-[9px] font-medium text-[--color-warning]">
                          VETO
                        </span>
                      )}
                    </div>
                    {rr.comment && <p className="mt-1 text-[--color-text-muted]">{rr.comment}</p>}
                    <p
                      className="mt-1 text-[10px] text-[--color-text-subtle]"
                      title={absolute(rr.responded_at)}
                    >
                      {relative(rr.responded_at)}
                    </p>
                  </li>
                ))}
              </ul>
            </TabsContent>
            <TabsContent value="activity" className="m-0 p-3">
              <ActivityTab requestId={r.id} />
            </TabsContent>
            <TabsContent value="files" className="m-0">
              <FilesTab
                workspaceId={ws_id}
                projectId={proj_id}
                assetId={r.design_asset_id}
                versionId={r.version_id}
              />
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
  versionId,
  assetId,
  approvalId,
}: {
  workspaceId: string
  projectId: string
  versionId: string
  assetId: string
  approvalId: string
}) {
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">Version</div>
      <p className="text-xs text-[--color-text-muted]">Anchored to a specific published version.</p>
      <Button asChild size="sm" variant="secondary" className="w-full">
        <Link
          to={`/workspace/${workspaceId}/project/${projectId}/asset/${assetId}/v/${versionId}?approval=${approvalId}`}
        >
          <ExternalLink className="mr-1 h-3.5 w-3.5" />
          Open in workspace
        </Link>
      </Button>
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
  chain: import('./queries').ApprovalChainRow[]
}) {
  if (chain.length <= 1) return null
  return (
    <div className="space-y-2 rounded-[--radius-md] border border-[--color-border] bg-[--color-surface] p-3 text-sm">
      <div className="text-[10px] uppercase tracking-wide text-[--color-text-subtle]">
        Supersession chain
      </div>
      <ul className="space-y-1">
        {chain.map((c) => (
          <li key={c.out_id}>
            <Link
              to={`/workspace/${workspaceId}/project/${projectId}/approval/${c.out_id}`}
              className={
                'flex items-center gap-2 rounded-[--radius-sm] px-2 py-1 text-xs ' +
                (c.out_id === currentId
                  ? 'bg-[--color-surface-2] font-medium'
                  : 'hover:bg-[--color-surface-2]')
              }
            >
              <span className="flex-1 truncate">{c.out_title ?? 'Untitled'}</span>
              <StateBadge state={c.out_status as WorkflowState} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  )
}

function ActivityTab({ requestId }: { requestId: string }) {
  const q = useQuery({
    queryKey: ['approval', requestId, 'activity'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('activity_events')
        .select('id, event_type, occurred_at, actor_profile_id, payload, subject_label')
        .eq('subject_id', requestId)
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
        <li
          key={e.id}
          className="rounded-[--radius-sm] px-2 py-1.5 text-xs hover:bg-[--color-surface-2]"
        >
          <div className="font-medium">{e.event_type}</div>
          <div
            className="text-[10px] text-[--color-text-subtle]"
            title={absolute(e.occurred_at as string)}
          >
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
