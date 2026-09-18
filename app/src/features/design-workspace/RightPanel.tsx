import { useSearchParams } from 'react-router'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/ui/tabs'
import { DetailsPanel } from './panels/DetailsPanel'
import { VersionsPanel } from './panels/VersionsPanel'
import { FilesPanel } from '@/features/files/FilesPanel'
import { CommentsPanel } from '@/features/comments/CommentsPanel'
import { ReviewsTabPanel } from '@/features/reviews/ReviewsTabPanel'
import { useCommentsForVersion } from '@/features/comments/queries'
import { useAnnotationsForVersion } from '@/features/annotations/queries'
import { useReviewsForVersion } from '@/features/reviews/queries'
import type { AssetRow } from '@/features/designs/queries'
import type { CollectionRow } from '@/features/collections/queries'
import type { DisciplineRow } from '@/features/disciplines/queries'
import type { AssetVersionRow } from './queries'
import type { VersionFileRow } from '@/features/files/queries'

interface Props {
  workspaceId: string
  projectId: string
  asset: AssetRow
  collections: CollectionRow[]
  disciplines: DisciplineRow[]
  versions: AssetVersionRow[]
  activeVersionId: string | null
  activeFileId: string | null
  isDraft: boolean
  files: VersionFileRow[]
  canEditAsset: boolean
  canArchiveAsset: boolean
  canEditProject: boolean
  canComment: boolean
  canResolveComment: boolean
  canEditOwnComment: boolean
  canCreateReview: boolean
  activeVersionPublished: boolean
  scopeQuery?: string
  onFocusAnnotation?: (annotationId: string) => void
  /** External ref for the composer trigger — the C hotkey uses this. */
  onFocusGeneralComposerRequestedRef?: React.MutableRefObject<(() => void) | null>
}

type Tab = 'details' | 'files' | 'comments' | 'versions' | 'reviews'

export function RightPanel({
  workspaceId,
  projectId,
  asset,
  collections,
  disciplines,
  versions,
  activeVersionId,
  activeFileId,
  isDraft,
  files,
  canEditAsset,
  canArchiveAsset,
  canEditProject,
  canComment,
  canResolveComment,
  canEditOwnComment,
  canCreateReview,
  activeVersionPublished,
  scopeQuery,
  onFocusAnnotation,
}: Props) {
  const [searchParams, setSearchParams] = useSearchParams()
  const rawTab = searchParams.get('tab')
  const tab: Tab =
    rawTab === 'files' || rawTab === 'versions' || rawTab === 'comments' || rawTab === 'reviews'
      ? (rawTab as Tab)
      : 'details'

  const setTab = (v: string) => {
    const next = new URLSearchParams(searchParams)
    if (v === 'details') next.delete('tab')
    else next.set('tab', v)
    setSearchParams(next, { replace: true })
  }

  // Unresolved-count badge on the Comments tab.
  const annotations = useAnnotationsForVersion(activeVersionId ?? undefined)
  const annotationIds = (annotations.data ?? []).map((a) => a.id)
  const commentsQ = useCommentsForVersion(activeVersionId ?? undefined, annotationIds)
  const unresolvedCount = (commentsQ.data ?? []).filter(
    (c) => c.parent_comment_id === null && c.resolved_at === null && !c.deleted_at,
  ).length

  const reviewsQ = useReviewsForVersion(activeVersionId ?? undefined)
  const reviewsBadgeCount = (reviewsQ.data ?? []).filter(
    (r) => r.status === 'open' || r.status === 'in_progress' || r.status === 'waiting',
  ).length

  return (
    <div className="flex h-full w-80 shrink-0 flex-col border-l border-[--color-border] bg-[--color-surface]">
      <Tabs value={tab} onValueChange={setTab} className="flex h-full flex-col">
        <TabsList>
          <TabsTrigger value="details">Details</TabsTrigger>
          <TabsTrigger value="files">
            Files
            {files.length > 0 && (
              <span className="ml-1 rounded-full bg-[--color-surface-2] px-1.5 text-[10px] text-[--color-text-muted]">
                {files.length}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value="comments">
            Comments
            {unresolvedCount > 0 && (
              <span className="ml-1 rounded-full bg-[--color-state-open-bg] px-1.5 text-[10px] text-[--color-state-open]">
                {unresolvedCount}
              </span>
            )}
          </TabsTrigger>
          <TabsTrigger value="versions">Versions</TabsTrigger>
          <TabsTrigger value="reviews">
            Reviews
            {reviewsBadgeCount > 0 && (
              <span className="ml-1 rounded-full bg-[--color-state-open-bg] px-1.5 text-[10px] text-[--color-state-open]">
                {reviewsBadgeCount}
              </span>
            )}
          </TabsTrigger>
        </TabsList>
        <div className="flex-1 overflow-auto">
          <TabsContent value="details" className="m-0">
            <DetailsPanel
              asset={asset}
              collections={collections}
              disciplines={disciplines}
              canEdit={canEditAsset}
              canArchive={canArchiveAsset}
              canEditProject={canEditProject}
            />
          </TabsContent>
          <TabsContent value="files" className="m-0">
            <FilesPanel
              workspaceId={workspaceId}
              projectId={projectId}
              assetId={asset.id}
              versionId={activeVersionId}
              files={files}
              activeFileId={activeFileId}
              isDraft={isDraft}
              scopeQuery={scopeQuery}
            />
          </TabsContent>
          <TabsContent value="comments" className="m-0">
            {activeVersionId ? (
              <CommentsPanel
                workspaceId={workspaceId}
                projectId={projectId}
                versionId={activeVersionId}
                canComment={canComment}
                canResolve={canResolveComment}
                canEditOwn={canEditOwnComment}
                onFocusAnnotation={onFocusAnnotation}
              />
            ) : (
              <div className="p-3 text-sm text-[--color-text-muted]">No version selected.</div>
            )}
          </TabsContent>
          <TabsContent value="versions" className="m-0">
            <VersionsPanel
              workspaceId={workspaceId}
              projectId={projectId}
              assetId={asset.id}
              versions={versions}
              activeVersionId={activeVersionId}
              currentVersionId={asset.current_version_id}
              scopeQuery={scopeQuery}
            />
          </TabsContent>
          <TabsContent value="reviews" className="m-0">
            <ReviewsTabPanel
              workspaceId={workspaceId}
              projectId={projectId}
              assetId={asset.id}
              versionId={activeVersionId}
              versionIsPublished={activeVersionPublished}
              canCreate={canCreateReview}
            />
          </TabsContent>
        </div>
      </Tabs>
    </div>
  )
}
