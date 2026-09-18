import { Navigate, useParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/ui/card'
import { Button } from '@/ui/button'
import { LoadingPage } from '@/ui/loading-page'
import { EmptyState } from '@/ui/empty-state'
import { Link } from 'react-router'

type Kind =
  | 'review'
  | 'approval'
  | 'comment'
  | 'annotation'
  | 'reviewer'
  | 'approver'
  | 'requirement'
  | 'release'
  | 'notification'

/**
 * Deep-link entry points. APP 006 wires review + reviewer kinds; APP 007
 * adds approval + approver; APP 008 adds requirement; APP 010 adds notification
 * (fallback that resolves to the workspace inbox with ?highlight=<id>).
 */
export function DeepLinkResolver({ kind }: { kind: Kind }) {
  const { id } = useParams<{ id: string }>()
  if (kind === 'comment') return <CommentDeepLink id={id ?? ''} />
  if (kind === 'annotation') return <AnnotationDeepLink id={id ?? ''} />
  if (kind === 'review') return <ReviewDeepLinkResolver id={id ?? ''} />
  if (kind === 'reviewer') return <ReviewerDeepLinkResolver id={id ?? ''} />
  if (kind === 'approval') return <ApprovalDeepLinkResolver id={id ?? ''} />
  if (kind === 'approver') return <ApproverDeepLinkResolver id={id ?? ''} />
  if (kind === 'requirement') return <RequirementDeepLinkResolver id={id ?? ''} />
  if (kind === 'release') return <ReleaseDeepLinkResolver id={id ?? ''} />
  if (kind === 'notification') return <NotificationDeepLinkResolver id={id ?? ''} />
  return <Placeholder kind={kind} id={id} />
}

/**
 * APP 010 §15.2: /deep/notification/:id fallback. Resolves by fetching the
 * notification's workspace and forwarding to /workspace/:ws_id/inbox?highlight=<id>.
 * Rare-use path (Freeze Index §15.2); the primary path is always the source
 * slice's own /deep/<kind>/:id.
 */
function NotificationDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'notification', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_notification', {
        p_notification_id: id,
      })
      if (error) throw error
      return data as { workspace_id: string } | null
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Notification not found" />
  return (
    <Navigate
      to={`/workspace/${q.data.workspace_id}/inbox?highlight=${id}`}
      replace
    />
  )
}

function ReleaseDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'release', id],
    enabled: Boolean(id),
    queryFn: async () => {
      // Accept either a UUID or an R-NNN code. UUID direct-lookup first; on miss,
      // fall through and let the empty-state render (code-based deep link uses a
      // distinct /deep/release-code/:code route reserved for a later slice).
      const { data, error } = await supabase
        .from('releases')
        .select('id, workspace_id, project_id')
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Release not found" />
  return (
    <Navigate
      to={`/workspace/${q.data.workspace_id}/project/${q.data.project_id}/release/${q.data.id}`}
      replace
    />
  )
}

function RequirementDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'requirement', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('requirements')
        .select('id, workspace_id, project_id')
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Requirement not found" />
  return (
    <Navigate
      to={`/workspace/${q.data.workspace_id}/project/${q.data.project_id}/requirement/${q.data.id}`}
      replace
    />
  )
}

function ApprovalDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'approval', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('approval_requests')
        .select('id, workspace_id, project_id')
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Approval not found" />
  return (
    <Navigate
      to={`/workspace/${q.data.workspace_id}/project/${q.data.project_id}/approval/${q.data.id}`}
      replace
    />
  )
}

function ApproverDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'approver', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('approval_request_approvers')
        .select(
          'id, approval_request_id, approval:approval_requests!approval_request_approvers_request_fk(id, workspace_id, project_id)',
        )
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Approver not found" />
  const ar = (q.data as unknown as { approval: { id: string; workspace_id: string; project_id: string } })
    .approval
  if (!ar) return <NotFound label="Approver not found" />
  return (
    <Navigate
      to={`/workspace/${ar.workspace_id}/project/${ar.project_id}/approval/${ar.id}?participant=${q.data.id}`}
      replace
    />
  )
}

function ReviewDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'review', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('reviews')
        .select('id, workspace_id, project_id')
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Review not found" />
  return (
    <Navigate
      to={`/workspace/${q.data.workspace_id}/project/${q.data.project_id}/review/${q.data.id}`}
      replace
    />
  )
}

function ReviewerDeepLinkResolver({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'reviewer', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('review_participants')
        .select('id, review_id, review:reviews!review_participants_review_fk(id, workspace_id, project_id)')
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Reviewer not found" />
  const r = (q.data as unknown as { review: { id: string; workspace_id: string; project_id: string } }).review
  if (!r) return <NotFound label="Reviewer not found" />
  return (
    <Navigate
      to={`/workspace/${r.workspace_id}/project/${r.project_id}/review/${r.id}?participant=${q.data.id}`}
      replace
    />
  )
}

function Placeholder({ kind, id }: { kind: Kind; id: string | undefined }) {
  return (
    <div className="flex min-h-full items-center justify-center p-6">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>{kind === 'review' ? 'Opening review…' : 'Opening approval…'}</CardTitle>
          <CardDescription>
            Deep-link resolution lands in a later slice.{' '}
            <code className="font-mono text-xs">{id?.slice(0, 8)}…</code>
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-[--color-text-muted]">
            The real resolver will fetch the {kind}'s workspace and project and forward you to the
            Design Workspace with the right panel focused.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}

/**
 * Fetch the comment, resolve to workspace URL. If target is version-scoped,
 * open ?tab=comments&comment=:id on the version. If annotation-scoped, forward
 * to the annotation deep link (which resolves further).
 */
function CommentDeepLink({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'comment', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('comments')
        .select(
          'id, parent_comment_id, target_version_id, target_annotation_id, target_design_asset_id',
        )
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      if (!data) return null

      // If it's a reply, resolve to the root's targeting.
      let root: {
        id: string
        target_version_id: string | null
        target_annotation_id: string | null
      } = data as never
      if (data.parent_comment_id) {
        const { data: rootData, error: rootErr } = await supabase
          .from('comments')
          .select('id, target_version_id, target_annotation_id')
          .eq('id', data.parent_comment_id)
          .maybeSingle()
        if (rootErr) throw rootErr
        if (rootData) root = rootData as never
      }

      if (root.target_annotation_id) {
        return {
          kind: 'redirect' as const,
          to: `/deep/annotation/${root.target_annotation_id}?comment=${root.id}`,
        }
      }
      if (root.target_version_id) {
        return {
          kind: 'version' as const,
          versionId: root.target_version_id,
          focusCommentId: root.id,
        }
      }
      return null
    },
  })

  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Comment not found" />
  if (q.data.kind === 'redirect') return <Navigate to={q.data.to} replace />

  return <ResolveByVersion versionId={q.data.versionId} focusComment={q.data.focusCommentId} />
}

function AnnotationDeepLink({ id }: { id: string }) {
  const q = useQuery({
    queryKey: ['deep', 'annotation', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('annotations')
        .select('id, asset_version_id, version_file_id')
        .eq('id', id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Annotation not found" />
  return (
    <ResolveByVersion
      versionId={q.data.asset_version_id}
      versionFileId={q.data.version_file_id}
      focusAnnotation={id}
    />
  )
}

/**
 * Second-hop resolver: given an asset_version_id, fetch the workspace/project/asset
 * and build the workspace URL with the right params.
 */
function ResolveByVersion({
  versionId,
  versionFileId,
  focusComment,
  focusAnnotation,
}: {
  versionId: string
  versionFileId?: string | null
  focusComment?: string
  focusAnnotation?: string
}) {
  const q = useQuery({
    queryKey: ['deep', 'version', versionId, versionFileId ?? null],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('asset_versions')
        .select('id, workspace_id, project_id, design_asset_id')
        .eq('id', versionId)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
  if (q.isLoading) return <LoadingPage />
  if (q.isError || !q.data) return <NotFound label="Version not found" />

  const v = q.data
  const params = new URLSearchParams()
  params.set('tab', 'comments')
  if (focusAnnotation) params.set('annotation', focusAnnotation)
  if (focusComment) params.set('comment', focusComment)
  const filePart = versionFileId ? `/file/${versionFileId}` : ''
  const url = `/workspace/${v.workspace_id}/project/${v.project_id}/asset/${v.design_asset_id}/v/${v.id}${filePart}?${params.toString()}`
  return <Navigate to={url} replace />
}

function NotFound({ label }: { label: string }) {
  return (
    <div className="p-8">
      <EmptyState
        title={label}
        description="It may have been deleted or you may not have access to it."
        action={
          <Button asChild size="sm" variant="secondary">
            <Link to="/">Return home</Link>
          </Button>
        }
      />
    </div>
  )
}
